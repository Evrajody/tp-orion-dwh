"""
Orchestrateur ETL Orion : transporte les données entre Postgres et SQL Server.
La logique de transformation est entièrement dans les procédures stockées T-SQL
(cf. mssql-etl/init/05..07_*.sql) — ce script ne fait que :

  1. extraire les jeux de données dénormalisés depuis Postgres OLTP
     (schéma `ops`, nomenclature française),
  2. charger les tables de staging dans SQL Server,
  3. déclencher etl.sp_run_pipeline (qui exécute toutes les sp_load_dim_*
     puis sp_load_fait_ventes),
  4. exporter dim.* et fact.* depuis SQL Server vers Postgres DWH
     (schéma `dw`, nomenclature française).

Planification : APScheduler (cron). Run-once forcé si ETL_RUN_ON_START=true.
"""
from __future__ import annotations

import logging
import os
import sys
import time
from contextlib import contextmanager
from datetime import datetime, timezone

import psycopg
import pyodbc
from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger("orchestrator")


# ---------------------------------------------------------------------------
# Connexions
# ---------------------------------------------------------------------------
def pg_conn(role: str) -> psycopg.Connection:
    cfg = {
        "host": os.environ[f"{role}_HOST"],
        "port": int(os.environ[f"{role}_PORT"]),
        "dbname": os.environ[f"{role}_DB"],
        "user": os.environ[f"{role}_USER"],
        "password": os.environ[f"{role}_PASSWORD"],
    }
    return psycopg.connect(**cfg)


def mssql_conn() -> pyodbc.Connection:
    cs = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={os.environ['MSSQL_HOST']},{os.environ['MSSQL_PORT']};"
        f"UID=sa;PWD={os.environ['MSSQL_SA_PASSWORD']};"
        f"DATABASE=OrionETL;TrustServerCertificate=yes;"
    )
    return pyodbc.connect(cs, autocommit=False)


@contextmanager
def both_connections():
    pg_oltp = pg_conn("OLTP")
    pg_dwh  = pg_conn("DWH")
    ms      = mssql_conn()
    try:
        yield pg_oltp, pg_dwh, ms
    finally:
        ms.close()
        pg_dwh.close()
        pg_oltp.close()


# ---------------------------------------------------------------------------
# Étape 1 — Extraction OLTP → SQL Server staging
# Les requêtes utilisent la nomenclature française (schéma ops.*).
# ---------------------------------------------------------------------------
EXTRACTS = {
    "staging.geographie_full": """
        SELECT v.ville_id, v.nom_ville, v.code_postal,
               r.nom_region,
               p.code_pays, p.nom_pays,
               c.nom_continent
          FROM ops.ville      v
          JOIN ops.region     r  ON r.region_id    = v.region_id
          JOIN ops.pays       p  ON p.pays_id      = r.pays_id
          JOIN ops.continent  c  ON c.continent_id = p.continent_id
    """,
    "staging.fournisseur_full": """
        SELECT f.fournisseur_id, f.nom_fournisseur,
               p.nom_pays, c.nom_continent
          FROM ops.fournisseur f
          JOIN ops.pays        p ON p.pays_id      = f.pays_id
          JOIN ops.continent   c ON c.continent_id = p.continent_id
    """,
    "staging.canal": """
        SELECT canal_id, code_canal, nom_canal FROM ops.canal_vente
    """,
    "staging.produit_full": """
        SELECT pr.produit_id, pr.nom_produit,
               g.nom_groupe_produit,
               cat.nom_categorie_produit,
               lp.nom_ligne_produit,
               f.fournisseur_id  AS fournisseur_id_naturel,
               f.nom_fournisseur,
               pr.actif
          FROM ops.produit            pr
          JOIN ops.groupe_produit     g   ON g.groupe_produit_id    = pr.groupe_produit_id
          JOIN ops.categorie_produit  cat ON cat.categorie_produit_id = g.categorie_produit_id
          JOIN ops.ligne_produit      lp  ON lp.ligne_produit_id    = cat.ligne_produit_id
          JOIN ops.fournisseur        f   ON f.fournisseur_id       = pr.fournisseur_id
    """,
    "staging.client_full": """
        SELECT c.client_id,
               c.nom || ' ' || c.prenom              AS nom_complet,
               c.sexe, c.date_naissance,
               gc.nom_groupe_client                  AS groupe_client,
               (cf.carte_fidelite_id IS NOT NULL)    AS a_carte_fidelite,
               v.nom_ville,
               p.nom_pays,
               cont.nom_continent,
               c.maj_le
          FROM ops.client          c
          LEFT JOIN ops.groupe_client gc ON gc.groupe_client_id = c.groupe_client_id
          LEFT JOIN ops.carte_fidelite cf ON cf.client_id        = c.client_id
          JOIN ops.ville           v    ON v.ville_id     = c.ville_id
          JOIN ops.region          r    ON r.region_id    = v.region_id
          JOIN ops.pays            p    ON p.pays_id      = r.pays_id
          JOIN ops.continent       cont ON cont.continent_id = p.continent_id
    """,
    "staging.employe_full": """
        SELECT e.employe_id,
               e.nom || ' ' || e.prenom        AS nom_complet,
               e.sexe, e.date_naissance, e.salaire,
               op.nom_org_pays                 AS org_pays,
               oc.nom_org_compagnie            AS org_compagnie,
               od.nom_org_departement          AS org_departement,
               os.nom_org_section              AS org_section,
               og.nom_org_groupe               AS org_groupe,
               (m.nom || ' ' || m.prenom)      AS nom_manager,
               e.date_embauche, e.date_depart,
               e.maj_le
          FROM ops.employe          e
          JOIN ops.org_groupe       og  ON og.org_groupe_id      = e.org_groupe_id
          JOIN ops.org_section      os  ON os.org_section_id     = og.org_section_id
          JOIN ops.org_departement  od  ON od.org_departement_id = os.org_departement_id
          JOIN ops.org_compagnie    oc  ON oc.org_compagnie_id   = od.org_compagnie_id
          JOIN ops.org_pays         op  ON op.org_pays_id        = oc.org_pays_id
          LEFT JOIN ops.employe     m   ON m.employe_id          = e.manager_id
    """,
    "staging.lignes_commande": """
        SELECT o.commande_id, l.numero_ligne, o.date_commande,
               o.client_id, o.employe_id, o.canal_id,
               l.produit_id, p.fournisseur_id,
               c.ville_id   AS cli_ville_id,
               l.quantite, l.prix_unitaire, l.cout_unitaire, l.pct_remise
          FROM ops.commande        o
          JOIN ops.ligne_commande  l  ON l.commande_id = o.commande_id
          JOIN ops.produit         p  ON p.produit_id  = l.produit_id
          JOIN ops.client          c  ON c.client_id   = o.client_id
         WHERE o.date_commande > %s
    """,
}

# Colonnes des tables de staging (ordre = ordre des SELECT ci-dessus)
COLUMNS = {
    "staging.geographie_full":  ["ville_id","nom_ville","code_postal","nom_region",
                                 "code_pays","nom_pays","nom_continent"],
    "staging.fournisseur_full": ["fournisseur_id","nom_fournisseur","nom_pays","nom_continent"],
    "staging.canal":            ["canal_id","code_canal","nom_canal"],
    "staging.produit_full":     ["produit_id","nom_produit","nom_groupe_produit",
                                 "nom_categorie_produit","nom_ligne_produit",
                                 "fournisseur_id_naturel","nom_fournisseur","actif"],
    "staging.client_full":      ["client_id","nom_complet","sexe","date_naissance",
                                 "groupe_client","a_carte_fidelite","nom_ville",
                                 "nom_pays","nom_continent","maj_le"],
    "staging.employe_full":     ["employe_id","nom_complet","sexe","date_naissance","salaire",
                                 "org_pays","org_compagnie","org_departement","org_section",
                                 "org_groupe","nom_manager","date_embauche","date_depart",
                                 "maj_le"],
    "staging.lignes_commande":  ["commande_id","numero_ligne","date_commande","client_id",
                                 "employe_id","canal_id","produit_id","fournisseur_id",
                                 "cli_ville_id","quantite","prix_unitaire","cout_unitaire",
                                 "pct_remise"],
}


def load_staging(pg_oltp, ms):
    """Vide chaque table de staging puis recharge depuis Postgres OLTP."""
    cur_ms = ms.cursor()
    cur_pg = pg_oltp.cursor()

    # Watermark côté SQL Server pour fait_ventes incrémental
    cur_ms.execute("SELECT last_value FROM etl.watermark WHERE job_name='fait_ventes'")
    row = cur_ms.fetchone()
    watermark = row[0] if row else datetime(1900, 1, 1, tzinfo=timezone.utc)

    for table, sql in EXTRACTS.items():
        cur_ms.execute(f"TRUNCATE TABLE {table};")
        params = (watermark,) if table == "staging.lignes_commande" else ()
        cur_pg.execute(sql, params)
        rows = cur_pg.fetchall()
        if not rows:
            log.info("staging %s : 0 ligne", table)
            continue
        cols = COLUMNS[table]
        placeholders = ",".join(["?"] * len(cols))
        cur_ms.fast_executemany = True
        cur_ms.executemany(
            f"INSERT {table} ({','.join(cols)}) VALUES ({placeholders})",
            rows,
        )
        log.info("staging %s : %d lignes chargées", table, len(rows))
    ms.commit()


# ---------------------------------------------------------------------------
# Étape 2 — Exécution du pipeline T-SQL
# ---------------------------------------------------------------------------
def run_pipeline(ms):
    cur = ms.cursor()
    log.info("exécution etl.sp_run_pipeline …")
    cur.execute("EXEC etl.sp_run_pipeline")
    while cur.nextset():
        pass
    ms.commit()


# ---------------------------------------------------------------------------
# Étape 3 — Export SQL Server → Postgres DWH
# ---------------------------------------------------------------------------
EXPORTS = [
    ("dim.dim_date",        "dw.dim_date"),
    ("dim.dim_canal",       "dw.dim_canal"),
    ("dim.dim_geographie",  "dw.dim_geographie"),
    ("dim.dim_fournisseur", "dw.dim_fournisseur"),
    ("dim.dim_produit",     "dw.dim_produit"),
    ("dim.dim_client",      "dw.dim_client"),
    ("dim.dim_employe",     "dw.dim_employe"),
    ("fact.fait_ventes",    "dw.fait_ventes"),
]


def push_to_dwh(ms, pg_dwh):
    cur_ms  = ms.cursor()
    cur_dwh = pg_dwh.cursor()

    # On vide d'un coup avec CASCADE pour éviter d'orchestrer l'ordre des FK.
    cur_dwh.execute(
        "TRUNCATE dw.fait_ventes, dw.dim_client, dw.dim_employe, "
        "dw.dim_produit, dw.dim_fournisseur, dw.dim_geographie, "
        "dw.dim_canal, dw.dim_date RESTART IDENTITY CASCADE;"
    )

    for src, dst in EXPORTS:
        cur_ms.execute(f"SELECT * FROM {src}")
        cols = [d[0] for d in cur_ms.description]
        rows = cur_ms.fetchall()
        if not rows:
            continue
        cols_quoted = ",".join(cols)
        with cur_dwh.copy(
            f"COPY {dst} ({cols_quoted}) FROM STDIN"
        ) as cp:
            for r in rows:
                cp.write_row(tuple(r))
        log.info("DWH %s : %d lignes écrites", dst, len(rows))
    pg_dwh.commit()


# ---------------------------------------------------------------------------
# Run principal
# ---------------------------------------------------------------------------
def run_full_pipeline():
    log.info("=== ETL run start ===")
    started = time.time()
    try:
        with both_connections() as (pg_oltp, pg_dwh, ms):
            load_staging(pg_oltp, ms)
            run_pipeline(ms)
            push_to_dwh(ms, pg_dwh)
        log.info("=== ETL run OK en %.1fs ===", time.time() - started)
    except Exception as exc:
        log.exception("ETL run FAILED : %s", exc)


def main():
    if os.getenv("ETL_RUN_ON_START", "true").lower() == "true":
        log.info("attente 15s pour démarrage SQL Server …")
        time.sleep(15)
        run_full_pipeline()

    sched = BlockingScheduler(timezone="UTC")
    sched.add_job(
        run_full_pipeline,
        CronTrigger(
            hour=int(os.getenv("ETL_DAILY_FACT_CRON_HOUR", "0")),
            minute=int(os.getenv("ETL_DAILY_FACT_CRON_MINUTE", "0")),
        ),
        id="etl_daily",
        name="ETL Orion — pipeline quotidien complet",
    )
    log.info("scheduler démarré.")
    try:
        sched.start()
    except (KeyboardInterrupt, SystemExit):
        sys.exit(0)


if __name__ == "__main__":
    main()
