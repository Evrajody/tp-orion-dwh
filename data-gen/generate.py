"""Générateur de données pour la base OLTP Orion (nomenclature française).

Volumétrie cible (énoncé p. 1) :
    - 700 employés (range 600-800)
    - 64 fournisseurs
    - 5 500 produits
    - 90 000 clients
    - 980 000 commandes

Lance ce script via :
    docker compose --profile seed run --rm data-gen
"""
from __future__ import annotations

import io
import os
import random
import time
from datetime import date, timedelta

import psycopg2
import psycopg2.extras
from faker import Faker

# ---------------------------------------------------------------------------
# Configuration via variables d'environnement
# ---------------------------------------------------------------------------
DSN = dict(
    host=os.environ["OLTP_HOST"],
    port=int(os.environ.get("OLTP_PORT", 5432)),
    dbname=os.environ["OLTP_DB"],
    user=os.environ["OLTP_USER"],
    password=os.environ["OLTP_PASSWORD"],
)
NB_EMPLOYES    = int(os.environ.get("NB_EMPLOYEES",    700))
NB_FOURNISSEURS= int(os.environ.get("NB_SUPPLIERS",     64))
NB_PRODUITS    = int(os.environ.get("NB_PRODUCTS",    5500))
NB_CLIENTS     = int(os.environ.get("NB_CUSTOMERS",  90000))
NB_COMMANDES   = int(os.environ.get("NB_ORDERS",    980000))
DATE_DEBUT     = date.fromisoformat(os.environ.get("DATE_START", "1998-01-01"))
DATE_FIN       = date.fromisoformat(os.environ.get("DATE_END",   "2002-12-31"))
SEED           = int(os.environ.get("SEED", 42))

random.seed(SEED)
fake = Faker("fr_FR")
Faker.seed(SEED)

PRENOMS_M = [fake.first_name_male()   for _ in range(200)]
PRENOMS_F = [fake.first_name_female() for _ in range(200)]
NOMS      = [fake.last_name()         for _ in range(500)]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def attendre_db(retries: int = 30, delay: float = 1.0) -> None:
    """Attend que Postgres réponde (utile au tout premier docker compose up)."""
    for i in range(retries):
        try:
            with psycopg2.connect(**DSN) as c:
                c.cursor().execute("SELECT 1")
            return
        except psycopg2.OperationalError as e:
            print(f"[wait_for_db] tentative {i+1}/{retries} : {e}")
            time.sleep(delay)
    raise SystemExit("Postgres OLTP injoignable.")


def date_aleatoire(debut: date, fin: date) -> date:
    return debut + timedelta(days=random.randint(0, (fin - debut).days))


def deja_peuplee(cur) -> bool:
    cur.execute("SELECT count(*) FROM ops.produit")
    return cur.fetchone()[0] > 0


def copy_rows(cur, table: str, columns: list[str], rows) -> None:
    """COPY haute performance via un buffer texte tab-separated."""
    buf = io.StringIO()
    for r in rows:
        buf.write(
            "\t".join(
                "\\N" if v is None
                else (v.isoformat() if isinstance(v, date)
                      else str(v).replace("\\", "\\\\")
                                  .replace("\t", " ")
                                  .replace("\n", " "))
                for v in r
            ) + "\n"
        )
    buf.seek(0)
    cur.copy_expert(
        f"COPY {table} ({', '.join(columns)}) FROM STDIN WITH (FORMAT TEXT, NULL '\\N')",
        buf,
    )


# ---------------------------------------------------------------------------
# Géographie
# ---------------------------------------------------------------------------
def gen_geographie(cur) -> list[int]:
    """Crée régions + villes (5 régions/pays, 5 villes/région)."""
    cur.execute("SELECT pays_id FROM ops.pays")
    pays_ids = [r[0] for r in cur.fetchall()]

    region_rows = []
    region_names_used = set()
    for pid in pays_ids:
        for _ in range(5):
            while True:
                name = fake.region() if hasattr(fake, "region") else fake.state()
                key = (name, pid)
                if key not in region_names_used:
                    region_names_used.add(key)
                    break
            region_rows.append((name, pid))

    psycopg2.extras.execute_values(
        cur,
        "INSERT INTO ops.region (nom_region, pays_id) VALUES %s "
        "ON CONFLICT DO NOTHING",
        region_rows,
    )
    cur.execute("SELECT region_id FROM ops.region")
    region_ids = [r[0] for r in cur.fetchall()]

    ville_rows = []
    for rid in region_ids:
        for _ in range(5):
            ville_rows.append((fake.city(), fake.postcode(), rid))
    psycopg2.extras.execute_values(
        cur,
        "INSERT INTO ops.ville (nom_ville, code_postal, region_id) VALUES %s",
        ville_rows,
    )
    cur.execute("SELECT ville_id FROM ops.ville")
    return [r[0] for r in cur.fetchall()]


# ---------------------------------------------------------------------------
# Fournisseurs
# ---------------------------------------------------------------------------
def gen_fournisseurs(cur, pays_ids: list[int]) -> None:
    rows = [
        (fake.company(), random.choice(pays_ids))
        for _ in range(NB_FOURNISSEURS)
    ]
    psycopg2.extras.execute_values(
        cur,
        "INSERT INTO ops.fournisseur (nom_fournisseur, pays_id) VALUES %s",
        rows,
    )


# ---------------------------------------------------------------------------
# Produits + historiques + remises
# ---------------------------------------------------------------------------
def gen_produits(cur) -> tuple[list[int], dict, dict]:
    cur.execute("SELECT groupe_produit_id FROM ops.groupe_produit")
    group_ids = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT fournisseur_id FROM ops.fournisseur")
    fournisseur_ids = [r[0] for r in cur.fetchall()]

    print(f"[produits] insertion de {NB_PRODUITS} produits …")
    prod_rows = []
    for _ in range(NB_PRODUITS):
        prod_rows.append((
            f"{fake.word().capitalize()} {fake.word().capitalize()} {random.randint(100, 9999)}",
            random.choice(group_ids),
            random.choice(fournisseur_ids),
            True,
            date_aleatoire(DATE_DEBUT - timedelta(days=365), DATE_DEBUT),
        ))
    psycopg2.extras.execute_values(
        cur,
        "INSERT INTO ops.produit (nom_produit, groupe_produit_id, fournisseur_id, "
        "                          actif, cree_le) VALUES %s "
        "RETURNING produit_id",
        prod_rows,
        page_size=2000,
    )
    produit_ids = [r[0] for r in cur.fetchall()]

    print("[produits] historique de prix (1 à 3 fenêtres par produit) …")
    prix_rows = []
    cache_prix: dict[int, list] = {}
    for pid in produit_ids:
        windows = []
        cursor_d = DATE_DEBUT - timedelta(days=180)
        while cursor_d < DATE_FIN:
            length = timedelta(days=random.randint(180, 720))
            end_d  = min(cursor_d + length, DATE_FIN + timedelta(days=365))
            windows.append((cursor_d, end_d))
            cursor_d = end_d + timedelta(days=1)
        for i, (sd, ed) in enumerate(windows):
            cout = round(random.uniform(5, 200), 2)
            prix = round(cout * random.uniform(1.3, 2.5), 2)
            end_val = None if i == len(windows) - 1 else ed
            prix_rows.append((pid, sd, end_val, cout, prix))
            cache_prix.setdefault(pid, []).append((sd, end_val, cout, prix))
    copy_rows(
        cur, "ops.historique_prix",
        ["produit_id", "date_debut", "date_fin", "cout", "prix_vente"],
        prix_rows,
    )

    print("[produits] remises (30 % des produits, 1 à 3 par produit) …")
    remise_rows = []
    cache_remise: dict[int, list] = {}
    for pid in produit_ids:
        if random.random() < 0.30:
            for _ in range(random.randint(1, 3)):
                sd  = date_aleatoire(DATE_DEBUT, DATE_FIN - timedelta(days=30))
                ed  = sd + timedelta(days=random.randint(7, 60))
                pct = round(random.uniform(0.05, 0.30), 4)
                remise_rows.append((pid, sd, ed, pct))
                cache_remise.setdefault(pid, []).append((sd, ed, pct))
    if remise_rows:
        copy_rows(
            cur, "ops.remise_produit",
            ["produit_id", "date_debut", "date_fin", "pct_remise"],
            remise_rows,
        )

    return produit_ids, cache_prix, cache_remise


# ---------------------------------------------------------------------------
# Employés
# ---------------------------------------------------------------------------
def gen_employes(cur, ville_ids: list[int]) -> None:
    cur.execute("SELECT org_groupe_id FROM ops.org_groupe")
    group_ids = [r[0] for r in cur.fetchall()]

    print(f"[employes] insertion de {NB_EMPLOYES} employés …")
    rows = []
    for _ in range(NB_EMPLOYES):
        sexe = random.choice(["M", "F"])
        prenom = random.choice(PRENOMS_M if sexe == "M" else PRENOMS_F)
        rows.append((
            random.choice(NOMS), prenom, sexe,
            fake.date_of_birth(minimum_age=22, maximum_age=63),
            date_aleatoire(DATE_DEBUT - timedelta(days=365 * 10), DATE_FIN),
            None,                                                # date_depart
            round(random.uniform(25_000, 120_000), 2),
            None,                                                # manager_id
            random.choice(group_ids),
            fake.street_address(),
            random.choice(ville_ids),
        ))
    psycopg2.extras.execute_values(
        cur,
        "INSERT INTO ops.employe "
        "(nom, prenom, sexe, date_naissance, date_embauche, date_depart, "
        " salaire, manager_id, org_groupe_id, rue, ville_id) VALUES %s "
        "RETURNING employe_id",
        rows,
        page_size=2000,
    )
    employe_ids = [r[0] for r in cur.fetchall()]

    # 1 employé sur 5 est manager d'autres employés
    managers = random.sample(employe_ids, max(1, len(employe_ids) // 5))
    updates = [(random.choice(managers), eid) for eid in employe_ids if eid not in managers]
    psycopg2.extras.execute_batch(
        cur,
        "UPDATE ops.employe SET manager_id = %s WHERE employe_id = %s",
        updates,
        page_size=1000,
    )


# ---------------------------------------------------------------------------
# Contrats employés
# ---------------------------------------------------------------------------
def gen_contrats(cur) -> None:
    """
    Patterns réalistes : 60% CDI direct, 25% CDD->CDI, 10% multi-CDD,
    5% stage / alternance / intérim. Les dates de contrat couvrent au
    moins l'intervalle [date_embauche, date_depart ou aujourd'hui].
    """
    cur.execute("SELECT employe_id, date_embauche, date_depart FROM ops.employe")
    employes = cur.fetchall()
    print(f"[contrats] génération pour {len(employes)} employés …")

    rows: list[tuple] = []
    for eid, d_embauche, d_depart in employes:
        d_fin_emploi = d_depart or DATE_FIN
        roll = random.random()

        if roll < 0.60:
            # 60 % : CDI unique, ouvert (date_fin = NULL si encore en poste)
            rows.append((eid, d_embauche, d_depart, "CDI"))

        elif roll < 0.85:
            # 25 % : 1 ou 2 CDD puis CDI
            cursor_d = d_embauche
            n_cdd = random.choice([1, 2])
            for _ in range(n_cdd):
                end = cursor_d + timedelta(days=random.randint(180, 540))
                if end >= d_fin_emploi:
                    end = d_fin_emploi
                rows.append((eid, cursor_d, end, "CDD"))
                cursor_d = end + timedelta(days=1)
                if cursor_d >= d_fin_emploi:
                    break
            if cursor_d < d_fin_emploi:
                rows.append((eid, cursor_d, d_depart, "CDI"))

        elif roll < 0.95:
            # 10 % : enchaînement de CDD sans CDI final
            cursor_d = d_embauche
            while cursor_d < d_fin_emploi:
                end = cursor_d + timedelta(days=random.randint(120, 365))
                if end >= d_fin_emploi:
                    end = d_fin_emploi
                rows.append((eid, cursor_d, end, "CDD"))
                cursor_d = end + timedelta(days=1)

        else:
            # 5 % : un seul contrat alternatif
            type_alt = random.choice(["Stage", "Alternance", "Interim", "Freelance"])
            end = d_embauche + timedelta(days=random.randint(120, 720))
            if end > d_fin_emploi:
                end = d_fin_emploi
            rows.append((eid, d_embauche, end, type_alt))

    copy_rows(
        cur, "ops.contrat_employe",
        ["employe_id", "date_debut", "date_fin", "type_contrat"],
        rows,
    )
    print(f"[contrats] {len(rows)} contrats générés.")


# ---------------------------------------------------------------------------
# Clients + cartes de fidélité
# ---------------------------------------------------------------------------
def gen_clients(cur, ville_ids: list[int]) -> None:
    cur.execute("SELECT groupe_client_id FROM ops.groupe_client")
    gc_ids = [r[0] for r in cur.fetchall()]

    print(f"[clients] insertion de {NB_CLIENTS} clients (par lots de 5000) …")
    inserted = 0
    BATCH = 5000
    while inserted < NB_CLIENTS:
        n = min(BATCH, NB_CLIENTS - inserted)
        rows = []
        for _ in range(n):
            sexe = random.choice(["M", "F"])
            prenom = random.choice(PRENOMS_M if sexe == "M" else PRENOMS_F)
            rows.append((
                random.choice(NOMS), prenom, sexe,
                fake.date_of_birth(minimum_age=18, maximum_age=85),
                random.choice(gc_ids),
                fake.street_address(),
                random.choice(ville_ids),
                random.random() < 0.85,
                date_aleatoire(DATE_DEBUT - timedelta(days=365), DATE_FIN),
            ))
        copy_rows(
            cur, "ops.client",
            ["nom", "prenom", "sexe", "date_naissance", "groupe_client_id",
             "rue", "ville_id", "actif", "cree_le"],
            rows,
        )
        inserted += n
        if inserted % 25_000 == 0:
            print(f"[clients]   {inserted}/{NB_CLIENTS}")

    # 25 % des clients ont une carte de fidélité — utilise l'id réel généré
    cur.execute("SELECT client_id FROM ops.client")
    client_ids = [r[0] for r in cur.fetchall()]
    print(f"[clients] cartes de fidélité (25 %) …")
    loyalty_rows = []
    for cid in client_ids:
        if random.random() < 0.25:
            loyalty_rows.append((
                cid,
                f"OSC-{cid:08d}",
                date_aleatoire(DATE_DEBUT, DATE_FIN),
            ))
    if loyalty_rows:
        copy_rows(
            cur, "ops.carte_fidelite",
            ["client_id", "numero_carte", "date_emission"],
            loyalty_rows,
        )


# ---------------------------------------------------------------------------
# Commandes — gros volume → COPY + lots de 10 000 commandes
# ---------------------------------------------------------------------------
def prix_a(cache: dict, pid: int, d: date) -> tuple[float, float] | None:
    for sd, ed, cout, prix in cache.get(pid, ()):
        if sd <= d and (ed is None or d <= ed):
            return cout, prix
    return None


def remise_a(cache: dict, pid: int, d: date) -> float:
    for sd, ed, pct in cache.get(pid, ()):
        if sd <= d <= ed:
            return pct
    return 0.0


def gen_commandes(cur, cache_prix: dict, cache_remise: dict) -> None:
    cur.execute("SELECT client_id FROM ops.client")
    client_ids = [r[0] for r in cur.fetchall()]
    cur.execute(
        "SELECT employe_id FROM ops.employe e "
        "WHERE org_groupe_id IN ("
        "   SELECT g.org_groupe_id FROM ops.org_groupe g "
        "   JOIN ops.org_section  s ON s.org_section_id = g.org_section_id "
        "   JOIN ops.org_departement d ON d.org_departement_id = s.org_departement_id "
        "   WHERE d.nom_org_departement = 'Ventes')"
    )
    employe_ventes = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT employe_id FROM ops.employe")
    tous_emp = [r[0] for r in cur.fetchall()]
    if not employe_ventes:
        employe_ventes = tous_emp

    cur.execute("SELECT canal_id FROM ops.canal_vente")
    canal_ids = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT produit_id FROM ops.produit")
    produit_ids = [r[0] for r in cur.fetchall()]

    print(f"[commandes] génération de {NB_COMMANDES} commandes par lots de 10 000 …")
    BATCH = 10_000
    total = 0
    while total < NB_COMMANDES:
        n = min(BATCH, NB_COMMANDES - total)

        # 1) entêtes de commande : on récupère leurs IDs réels
        entetes = []
        for _ in range(n):
            d = date_aleatoire(DATE_DEBUT, DATE_FIN)
            # saisonnalité : 30 % de chance de retomber sur novembre/décembre
            if d.month in (11, 12) and random.random() < 0.30:
                d = date_aleatoire(date(d.year, 11, 1), date(d.year, 12, 31))
            entetes.append((
                d,
                random.choice(client_ids),
                random.choice(employe_ventes),
                random.choice(canal_ids),
                0,
            ))
        psycopg2.extras.execute_values(
            cur,
            "INSERT INTO ops.commande "
            "(date_commande, client_id, employe_id, canal_id, montant_total) "
            "VALUES %s RETURNING commande_id, date_commande",
            entetes,
            page_size=5000,
        )
        rows_returned = cur.fetchall()
        commande_ids   = [r[0] for r in rows_returned]
        commande_dates = [r[1] for r in rows_returned]

        # 2) lignes de commande (1 à 5 par commande) — COPY direct
        ligne_rows = []
        for cmd_id, d in zip(commande_ids, commande_dates):
            n_lignes = random.randint(1, 5)
            chosen = random.sample(produit_ids, n_lignes)
            for numero, pid in enumerate(chosen, start=1):
                pr = prix_a(cache_prix, pid, d) or (10.0, 20.0)
                cout, prix = pr
                qte  = random.randint(1, 5)
                pct  = remise_a(cache_remise, pid, d)
                ligne_rows.append((cmd_id, numero, pid, qte, prix, cout, pct))
        copy_rows(
            cur, "ops.ligne_commande",
            ["commande_id", "numero_ligne", "produit_id", "quantite",
             "prix_unitaire", "cout_unitaire", "pct_remise"],
            ligne_rows,
        )

        # 3) recalcul du montant_total pour ce lot
        cur.execute(
            "UPDATE ops.commande o SET montant_total = sub.total "
            "FROM (SELECT commande_id, "
            "             SUM(quantite * prix_unitaire * (1 - pct_remise)) AS total "
            "      FROM ops.ligne_commande "
            "      WHERE commande_id = ANY(%s) GROUP BY commande_id) sub "
            "WHERE o.commande_id = sub.commande_id",
            (commande_ids,),
        )

        total += n
        # commit intermédiaire pour limiter la WAL et la mémoire
        cur.connection.commit()
        print(f"[commandes]   {total}/{NB_COMMANDES} (lot de {n}, {len(ligne_rows)} lignes)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    attendre_db()
    print(f"[seed] cible : {NB_EMPLOYES} employés, {NB_FOURNISSEURS} fournisseurs, "
          f"{NB_PRODUITS} produits, {NB_CLIENTS} clients, {NB_COMMANDES} commandes")
    conn = psycopg2.connect(**DSN)
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            if deja_peuplee(cur):
                print("[seed] base déjà peuplée, abandon.")
                return
            print("[seed] géographie …")
            ville_ids = gen_geographie(cur)
            cur.execute("SELECT pays_id FROM ops.pays")
            pays_ids = [r[0] for r in cur.fetchall()]
            print("[seed] fournisseurs …")
            gen_fournisseurs(cur, pays_ids)
            print("[seed] produits + prix + remises …")
            _, cache_prix, cache_remise = gen_produits(cur)
            print("[seed] employés …")
            gen_employes(cur, ville_ids)
            print("[seed] contrats employés …")
            gen_contrats(cur)
            print("[seed] clients + cartes fidélité …")
            gen_clients(cur, ville_ids)
            conn.commit()
            print("[seed] commandes + lignes …")
            gen_commandes(cur, cache_prix, cache_remise)
        conn.commit()
        print("[seed] OK ✓")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
