# TP1 — Société Orion : Data Warehouse complet

> Mise en place opérationnelle d'un entrepôt de données pour la société Orion
> (énoncé : *les TP-ED-ENEAM 2026*, TP n°1).
>
> **Architecture retenue** : bases OP et DWH en **PostgreSQL** (Docker),
> processus ETL en **procédures stockées T-SQL sur SQL Server** (Docker),
> orchestré par un thin transporter Python.
>
> **Nomenclature française** : tables OLTP (`ops.client`, `ops.produit`,
> `ops.commande`, `ops.fournisseur`, …) et dimensions DWH (`dw.dim_client`,
> `dw.dim_produit`, `dw.fait_ventes`, …) en français.
>
> **Volumétrie cible** (énoncé) : 700 employés · 64 fournisseurs ·
> 5 500 produits · 90 000 clients · 980 000 commandes (~2,5 M lignes).
> Ajustable dans `.env`.

## 1. Ce que livre ce projet

| Livrable                          | Emplacement                              |
|-----------------------------------|------------------------------------------|
| Modélisation OP + transition + DW | [`doc/MODELISATION.md`](doc/MODELISATION.md) |
| Modélisation UML complète         | [`doc/UML.md`](doc/UML.md) — 11 diagrammes |
| Poster UML monopage (A0)          | [`doc/rapport/uml-poster.pdf`](doc/rapport/uml-poster.pdf) |
| 11 PDF UML individuels (A3)       | [`doc/rapport/build/uml-individual/`](doc/rapport/build/uml-individual/) |
| Rapport PDF (~30 p)               | [`doc/rapport/rapport.pdf`](doc/rapport/rapport.pdf) — `./build.sh` pour compiler |
| Schéma OLTP (3NF)                 | `oltp/init/01_schema.sql`                |
| Référentiels statiques OLTP       | `oltp/init/02_static_data.sql`           |
| Schéma DWH (étoile)               | `dwh/init/01_schema.sql`                 |
| Générateur de données (Faker)    | `data-gen/generate.py`                   |
| **ETL T-SQL (SQL Server)**        | [`mssql-etl/init/`](mssql-etl/init/) — 7 scripts T-SQL |
| Orchestrateur Python              | [`orchestrator/orchestrate.py`](orchestrator/orchestrate.py) |
| Requêtes analytiques (15 questions)| `analytics/queries.sql`                  |
| Stack Docker complète             | `docker-compose.yml`                     |

## 2. Topologie

```
       Adminer × 3 instances dédiées (accès isolés)
       ┌─────────────────┐ ┌─────────────────┐ ┌──────────────────┐
       │ adminer-oltp    │ │ adminer-dwh     │ │ adminer-mssql    │
       │ http://...:8080 │ │ http://...:8081 │ │ http://...:8082  │
       └────────┬────────┘ └────────┬────────┘ └─────────┬────────┘
                             │        │
              ┌──────────────▼─┐    ┌─▼─────────────┐
   data-gen → │  postgres-oltp │    │ postgres-dwh  │
   (Faker)    │  (orion_oltp)  │    │ (orion_dwh)   │
              └────────▲───────┘    └───────▲───────┘
                       │                    │
                       │ extract            │ COPY
                       │                    │
                ┌──────┴────────────────────┴──────┐
                │           orchestrator           │  ← Python · APScheduler
                │     (transporte les données)     │
                └──────────────┬─────────┬─────────┘
                               │         │
                       INSERT  │         │  EXEC sp_run_pipeline
                      staging  ▼         ▼  + SELECT dim/fact
                       ┌────────────────────────┐
                       │       mssql-etl        │
                       │    SQL Server 2022     │  ← logique ETL en T-SQL
                       │  (OrionETL : staging,  │     (procédures stockées)
                       │   etl, dim, fact)      │
                       └────────────────────────┘
```

## 3. Démarrage rapide

Pré-requis : Docker + Docker Compose v2.

```fish
cd ~/dev-laboratory/tp-ed-eneam/tp1-orion

# 1) Démarrer Postgres OLTP + DWH + SQL Server + orchestrator + Adminer
docker compose up -d --build

# 2) Peupler la base OLTP avec des données fictives (one-shot)
docker compose --profile seed run --rm data-gen

# 3) Forcer un cycle ETL immédiat (sinon il s'exécute selon le cron)
docker compose restart orchestrator
```

Vérifier que tout tourne :

```fish
docker compose ps                       # 5 services up + healthy
docker compose logs -f orchestrator     # extract / EXEC / push
docker compose logs -f mssql-etl        # init T-SQL
```

Accès :

**Trois instances Adminer dédiées** (une par base, accès indépendants) :

| Instance         | URL                   | Driver | Serveur réseau | Utilisateur | Mot de passe        | Base       |
|------------------|-----------------------|--------|----------------|-------------|---------------------|------------|
| **adminer-oltp** | http://localhost:8080 | pgsql  | postgres-oltp  | orion       | orion_pwd           | orion_oltp |
| **adminer-dwh**  | http://localhost:8081 | pgsql  | postgres-dwh   | dwh         | dwh_pwd             | orion_dwh  |
| **adminer-mssql**| http://localhost:8082 | mssql  | mssql-etl      | sa          | Orion!StrongPwd2026 | OrionETL   |

Le serveur et le driver sont **pré-remplis** par instance (`ADMINER_DEFAULT_SERVER`,
`ADMINER_DEFAULT_DRIVER`) — il suffit d'entrer les identifiants.

**Accès direct aux bases** (sans Adminer) :

| Base              | Port hôte       | Identifiants                              |
|-------------------|-----------------|-------------------------------------------|
| Postgres OLTP     | localhost:5433  | orion / orion_pwd / orion_oltp            |
| Postgres DWH      | localhost:5434  | dwh / dwh_pwd / orion_dwh                 |
| SQL Server ETL    | localhost:1433  | sa / Orion!StrongPwd2026 / OrionETL       |

Tous les paramètres (volumes générés, cadence ETL, dates, mots de passe) sont
dans `.env`.

## 4. Lancer les requêtes analytiques

```fish
docker compose exec postgres-dwh \
    psql -U dwh -d orion_dwh -f /dev/stdin < analytics/queries.sql
```

Ou via Adminer DWH (http://localhost:8081) → SQL command → coller un bloc.

## 5. Inspecter le moteur ETL T-SQL

```fish
# Connexion sqlcmd dans le container
docker compose exec mssql-etl /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -No -d OrionETL

# Journal des runs (tabulaire)
docker compose exec mssql-etl /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -No -d OrionETL \
    -Q "SELECT TOP 10 job_name, started_at, status, rows_in, rows_out
        FROM etl.run_log ORDER BY run_id DESC"

# Re-exécuter manuellement le pipeline
docker compose exec mssql-etl /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -No -d OrionETL \
    -Q "EXEC etl.sp_run_pipeline"
```

## 6. Fréquence d'exécution

| Job                       | Cadence (UTC)       | Var. .env                                  |
|---------------------------|---------------------|--------------------------------------------|
| Pipeline complet          | 00:00 quotidien     | `ETL_DAILY_FACT_CRON_HOUR`/`...MINUTE`     |
| Bootstrap au démarrage    | si `=true`          | `ETL_RUN_ON_START=true`                    |

Pour changer la cadence :

```fish
# édite .env puis :
docker compose up -d orchestrator
```

## 7. Mettre la main à la pâte

```fish
# Forcer un re-chargement complet de fait_ventes
docker compose exec mssql-etl /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -No -d OrionETL \
    -Q "TRUNCATE TABLE fact.fait_ventes;
        DELETE FROM etl.watermark WHERE job_name='fait_ventes';"
docker compose restart orchestrator
```

## 8. Tear down

```fish
docker compose down            # garde les volumes
docker compose down -v         # supprime aussi les volumes (reset complet)
```
