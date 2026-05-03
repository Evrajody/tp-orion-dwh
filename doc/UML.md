# TP1 — Société Orion : Modélisation UML complète

> Ce document accompagne `MODELISATION.md` (qui couvre la couche relationnelle 3NF
> et le schéma en étoile) en apportant la **vue UML** du système : acteurs, objets
> métier, comportements, architecture logicielle et déploiement. Les diagrammes
> sources sont en Mermaid dans `rapport/diagrams/` (préfixe `1x-uml-…` /
> `2x-uml-…`) ; ils sont compilés en PDF par `rapport/build.sh`.

## 0. Carte des diagrammes

| #  | Type UML 2.x              | Fichier source                              | Vise à répondre à…                                              |
|----|---------------------------|---------------------------------------------|------------------------------------------------------------------|
| 10 | Cas d'utilisation         | `10-uml-usecase.mmd`                        | *Qui* utilise le SI décisionnel et *pour quoi* ?                 |
| 11 | Classes (modèle métier)   | `11-uml-class.mmd`                          | *Quels concepts* manipule-t-on et *comment se relient-ils* ?     |
| 12 | Séquence — passage commande | `12-uml-sequence-order.mmd`               | *Comment* une commande est-elle créée côté OLTP ?                |
| 13 | Séquence — job ETL SCD2   | `13-uml-sequence-etl.mmd`                   | *Comment* le DWH est-il alimenté en historisant ?                |
| 14 | Activité — cycle commande | `14-uml-activity-order.mmd`                 | *Quel flux décisionnel* derrière une vente ?                     |
| 15 | Activité — pipeline ETL   | `15-uml-activity-etl.mmd`                   | *Comment s'orchestrent* les jobs dim/SCD2/fact ?                 |
| 16 | États — commande          | `16-uml-state-order.mmd`                    | *Quels états* traverse une commande ?                            |
| 17 | États — contrat employé   | `17-uml-state-contract.mmd`                 | *Quel cycle de vie* pour un `contrat_employe` ?                  |
| 18 | Composants                | `18-uml-component.mmd`                      | *Quels modules* logiciels et *quelles interfaces* exposées ?     |
| 19 | Déploiement               | `19-uml-deployment.mmd`                     | *Sur quels nœuds* s'exécutent ces modules ?                      |
| 20 | Packages                  | `20-uml-package.mmd`                        | *Comment* organiser les sous-domaines et leurs dépendances ?     |

> **Note technique** : Mermaid ne dispose pas d'une syntaxe « use case » native.
> Les acteurs sont représentés par des nœuds étiquetés `👤` et les cas
> d'utilisation par des ellipses arrondies — la sémantique UML reste
> conventionnelle (associations, `«include»`, `«extend»`).

---

## 1. Diagramme de cas d'utilisation (`10-uml-usecase.mmd`)

### 1.1 Acteurs

| Acteur                | Type         | Rôle                                                                 |
|-----------------------|--------------|----------------------------------------------------------------------|
| Analyste décisionnel  | Humain       | Construit et exécute les requêtes analytiques, les rapports.         |
| Directeur commercial  | Humain       | Consomme les analyses (produits phares, marges, commerciaux).        |
| Direction marketing   | Humain       | Pilote les remises, segmente les clients.                            |
| Direction RH          | Humain       | Étudie la performance des commerciaux par sexe, âge, salaire.        |
| Data engineer (DBA)   | Humain       | Administre l'ETL, supervise les jobs, traite les incidents.          |
| ETL Scheduler         | Système      | APScheduler ; déclenche les jobs aux heures cron.                    |
| Système OLTP          | Système ext. | Source de vérité opérationnelle (`ops.*`) — cible des extractions.   |

### 1.2 Cas d'utilisation principaux

Tous les cas analytiques sont issus directement de l'énoncé (questions p. 3 du PDF).

- **UC-01 — Analyser le top des ventes** : produits qui se vendent le mieux.
- **UC-02 — Détecter les produits en perte de vitesse** : décroissance YoY.
- **UC-03 — Calculer la marge** par groupe, ligne, période.
- **UC-04 — Évaluer l'impact des remises** : corrélation remise → ventes / marge.
- **UC-05 — Classer les commerciaux** par sexe, âge, salaire, pays.
- **UC-06 — Segmenter les clients** : groupes, rentabilité.
- **UC-07 — Analyser les fournisseurs** : qui propose des produits rentables ?
- **UC-08 — Statistiques du CA** : moyenne, écart-type, test de moyenne H/F.
- **UC-09 — Variables explicatives** du CA (analyse multivariée).
- **UC-10 — Charger l'entrepôt** : exécution des jobs ETL planifiés.
- **UC-11 — Superviser ETL** : logs, watermark, reprise sur incident.
- **UC-12 — Extraire OLTP** : extraction incrémentale (inclus par UC-10).
- **UC-13 — S'authentifier** : prérequis (inclus par les UC analytiques).

### 1.3 Relations remarquables

- `UC-10 «include» UC-12` : on n'imagine pas charger sans extraire.
- `UC-11 «extend» UC-10` : la supervision est optionnelle (active si erreur ou
  si le DBA souhaite consulter `etl_run_log`).
- `UC-01, UC-05, UC-08 «include» UC-13` : authentification systématique pour
  les analyses (matérialise la traçabilité audit).

---

## 2. Diagramme de classes (`11-uml-class.mmd`)

### 2.1 Choix de modélisation

- **Hiérarchie `Person` abstraite** factorisant `firstName / lastName / gender /
  birthDate` entre `Employee` et `Customer`. En OLTP cette généralisation est
  *aplatie* (deux tables distinctes) — c'est le mapping habituel d'une héritage
  UML par classe concrète.
- **Compositions fortes** :
  - `SalesOrder` ◆──> `SalesOrderLine` : une ligne n'existe pas sans son ordre
    parent (cascade `ON DELETE`).
  - `OrgCountry → OrgCompany → OrgDepartment → OrgSection → OrgGroup` : la
    composition matérialise la hiérarchie organisationnelle à 5 niveaux exigée
    par l'énoncé.
  - `ProductLine → ProductCategory → ProductGroup → Product` : idem pour la
    hiérarchie produit à 4 niveaux.
- **Agrégation faible** entre `Customer` et `LoyaltyCard` (1↔0..1) : la carte
  est un attribut détachable (un client peut perdre sa carte sans cesser
  d'exister).
- **Auto-référence** sur `Employee` (manager hiérarchique, multiplicité `0..1`
  → `*`).
- **Méthodes métier** au niveau classe : `Produit.prixCourant(date)`,
  `LigneCommande.montantNet()`, `Employe.estActif()` — elles documentent les
  invariants exécutoires (calculs reproduits dans `fait_ventes`).

### 2.2 Correspondance classe ↔ table OLTP

| Classe UML            | Table `ops.*`              | Notes                                                |
|-----------------------|----------------------------|------------------------------------------------------|
| Continent             | `continent`                | —                                                    |
| Pays                  | `pays`                     | —                                                    |
| Region                | `region`                   | —                                                    |
| Ville                 | `ville`                    | —                                                    |
| OrgPays…OrgGroupe     | `org_pays`…`org_groupe`    | hiérarchie 5 niveaux                                 |
| Employe               | `employe`                  | auto-référence `manager_id`                          |
| ContratEmploye        | `contrat_employe`          | un employé peut avoir 0..n contrats successifs       |
| Client                | `client`                   | héritage logique de `Personne`                       |
| GroupeClient          | `groupe_client`            | classification d'achat                               |
| CarteFidelite         | `carte_fidelite`           | 1-1 optionnelle avec `client`                        |
| Fournisseur           | `fournisseur`              | rattaché à `Pays`                                    |
| LigneProduit…Produit  | `ligne_produit`…`produit`  | hiérarchie 4 niveaux                                 |
| HistoriquePrix        | `historique_prix`          | intervalle `[date_debut, date_fin]`                  |
| RemiseProduit         | `remise_produit`           | période de validité explicite                        |
| CanalVente            | `canal_vente`              | référentiel MAGASIN / CATALOGUE / INTERNET           |
| Commande              | `commande`                 | grain en-tête                                        |
| LigneCommande         | `ligne_commande`           | grain ligne (= grain `fait_ventes`)                  |

---

## 3. Diagrammes de séquence

### 3.1 Passage de commande (`12-uml-sequence-order.mmd`)

Représente le **scénario nominal** côté OLTP. Points saillants :

1. La tarification est résolue *au moment de la commande* via
   `historique_prix` (intervalle qui couvre `today`) — c'est ce qui
   permettra plus tard à `fait_ventes` de mémoriser `prix_unitaire` et
   `cout_unitaire` « à l'époque ».
2. La remise éventuelle (`remise_produit`) est appliquée dans le même appel
   de service (cohérence de la mesure).
3. Toute la création (`commande` + `N × ligne_commande` + recalcul
   `montant_total`) tient dans une **transaction unique** — invariant sur la
   somme des lignes.
4. La branche `opt` capture la mise à jour de `carte_fidelite` quand le
   client est adhérent (UC-04 / UC-06).

### 3.2 Job ETL SCD2 (`13-uml-sequence-etl.mmd`)

Décrit le chargement de `dim_client` selon **SCD type 2** :

1. Le scheduler déclenche le job ; un identifiant `run_id` est créé dans
   `etl.run_log`.
2. Le job calcule un `hash_ligne` (SHA-256) sur les champs sensibles (groupe,
   ville, région, pays).
3. Pour chaque clé naturelle :
   - **nouvelle** → insert ;
   - **hash inchangé** → no-op (gain CPU) ;
   - **hash changé** → fermeture de la version courante (`effectif_au`,
     `est_courant = FALSE`) puis insertion d'une nouvelle ligne courante.
4. Le watermark est mis à jour ; `etl.run_log` est marqué `SUCCESS`.

Ce pattern est appliqué à l'identique pour `dim_employe` (suivi salaire,
section, manager).

---

## 4. Diagrammes d'activité

### 4.1 Cycle d'une commande (`14-uml-activity-order.mmd`)

Couvre du panier au COMMIT, avec deux **points de décision** :

- **Disponibilité stock** — sortie alternative vers refus / proposition de
  remplacement.
- **Adhérent fidélité** — bifurcation pour l'attribution de points.

Le diagramme montre clairement que le calcul du prix précède l'application de
la remise, et que `montant_total` est calculé *avant* COMMIT (invariant
contrôlé en base).

### 4.2 Pipeline ETL (`15-uml-activity-etl.mmd`)

Le pipeline est exécuté par `etl.sp_run_pipeline` (T-SQL) après que
l'orchestrateur a chargé les tables `staging.*` :

- `sp_load_dim_date` (bootstrap)
- `sp_load_dim_canal / dim_geographie / dim_fournisseur / dim_produit`
  (SCD1 full reload)
- `sp_load_dim_client / dim_employe` (SCD2 merge via `hash_ligne`)
- `sp_load_fait_ventes` (incrémental sur `date_commande > watermark`)

Chaque procédure stockée journalise un run dans `etl.run_log`. Le job de
faits embarque sa propre décision « lignes nouvelles ? » pour éviter les
passes à vide.

---

## 5. Diagrammes d'états

### 5.1 Cycle de vie d'une commande (`16-uml-state-order.mmd`)

États : `Draft → Validated → PaymentPending → Paid → Preparing → Shipped →
Delivered → Closed`. Boucles de retry sur `PaymentFailed` ; chemin de retour
`Delivered → ReturnRequested → Refunded → Closed`. La note précise que
l'enregistrement effectif dans `commande` correspond à l'état `Paid` : la
table OLTP n'instancie que des commandes qui ont franchi la barre du
paiement (compatible avec le grain de `fait_ventes`).

### 5.2 Contrat employé (`17-uml-state-contract.mmd`)

États : `Draft → Active → (Suspended | Renewed | Expired | Terminated)`. Un
contrat « courant » au sens de la base est l'état `Active` ; matérialisé par
`date_fin IS NULL OR date_fin >= today`. Utile pour `dim_employe.est_courant`.

---

## 6. Diagramme de composants (`18-uml-component.mmd`)

Cinq composants déployables :

| Composant   | Stéréotype | Rôle                                                |
|-------------|------------|-----------------------------------------------------|
| `data-gen`  | component  | Peuplement Faker → OLTP (one-shot, `--profile seed`)|
| `etl`       | component  | Jobs Python + APScheduler ; long-running           |
| `Adminer`   | component (UI) | UI web multi-SGBD : Postgres OLTP/DWH **et** SQL Server |
| `orion_oltp`| database   | Source `ops.*` — interface SQL/JDBC                 |
| `orion_dwh` | database   | Cible `dw.*` — interface SQL/JDBC                   |

Les **interfaces fournies/requises** sont matérialisées : SQL/JDBC sur
`ops.*`, SQL/JDBC sur `dw.*`, TDS sur `OrionETL`, HTTP :8080 pour Adminer. La configuration
partagée (`.env`) est représentée comme une dépendance externe consommée par
les trois composants Python.

---

## 7. Diagramme de déploiement (`19-uml-deployment.mmd`)

Topologie physique :

- **1 hôte Linux** (poste étudiant)
- **1 environnement d'exécution** Docker Engine
- **1 réseau interne** `orion-net` isolant les conteneurs
- **5 conteneurs** (`postgres-oltp`, `postgres-dwh`, `mssql-etl`,
  `orchestrator`, `data-gen`, `adminer`)
- **3 volumes persistants** (`oltp_data`, `dwh_data`, `mssql_data`)

Les artefacts déployés (fichiers SQL d'init, scripts Python/T-SQL,
`adminer/index.php`) sont attachés à chaque conteneur via dépendance
`«deploy»`. Les ports exposés à l'hôte (`5433`, `5434`, `8080`) sont les
points d'entrée externes.

---

## 8. Diagramme de packages (`20-uml-package.mmd`)

Trois super-packages :

- **`ops` (OLTP)** — 5 sous-packages selon les sous-domaines métier
  (`geo`, `org_rh`, `produits`, `clients`, `ventes`).
- **`OrionETL` (SQL Server)** — `staging`, `dim`, `fact`, `etl`.
- **`dw` (DWH étoile)** — `dimensions`, `faits`.
- **`app` (containers)** — `data-gen`, `orchestrator`, `analytics`.

Les dépendances `«use»` orientent le sens des références (clé étrangère ou
import). On lit que :

- `sales` dépend de tous les autres packages OLTP (logique : c'est le
  carrefour transactionnel).
- `facts` dépend de `dimensions` et `etl_meta`.
- `etl` lit `ops` et écrit dans `dw` ; `analytics` lit `dw` ; `data-gen` écrit
  dans `ops`. Aucun cycle.

---

## 9. Cohérence avec la modélisation relationnelle

Cette modélisation UML **n'invalide pas** `MODELISATION.md` : elle l'enrichit
en ajoutant le **comportement** (UC, séquence, activité, états) et
l'**architecture** (composants, déploiement, packages) qui ne s'expriment pas
en SQL ou ERD.

Les correspondances clés :

| Concept UML                            | Concept relationnel                                  |
|----------------------------------------|------------------------------------------------------|
| Composition `Commande ◆ LigneCommande` | FK `ligne_commande.commande_id` + `ON DELETE CASCADE`|
| Auto-référence `Employe.manager`       | `employe.manager_id` REFERENCES `employe`            |
| `Produit.prixCourant(date)`            | Vue `v_prix_produit_a`                               |
| Activité ETL « hash changé ? »         | Pattern SCD2 (`hash_ligne`, `est_courant`)           |
| État `Commande.Paid`                   | Existence d'un tuple `commande`                      |
| Composant `orchestrator`               | Service Docker `orchestrator` (long-running)         |

---

## 10. Compilation

```fish
cd ~/dev-laboratory/tp-ed-eneam/tp1-orion/doc/rapport
./build.sh                # rend tous les .mmd → build/*.pdf et compile rapport.pdf
```

Les diagrammes UML sont alors disponibles dans `doc/rapport/build/` :

```
build/10-uml-usecase.pdf
build/11-uml-class.pdf
build/12-uml-sequence-order.pdf
build/13-uml-sequence-etl.pdf
build/14-uml-activity-order.pdf
build/15-uml-activity-etl.pdf
build/16-uml-state-order.pdf
build/17-uml-state-contract.pdf
build/18-uml-component.pdf
build/19-uml-deployment.pdf
build/20-uml-package.pdf
```
