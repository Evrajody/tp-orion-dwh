# TP1 — Société Orion : Modélisation OP & DW

> Ce document explique :
> 1. La modélisation **opérationnelle** 3NF (OLTP) — schéma `ops`.
> 2. La **transition** méthodologique OLTP → modélisation dimensionnelle.
> 3. La modélisation **dimensionnelle** en étoile (DWH) — schéma `dw`.
> 4. L'architecture **ETL** : SQL Server (procédures stockées T-SQL) +
>    orchestrateur Python qui ferraille les données entre Postgres et
>    SQL Server.

---

## 1. Modélisation opérationnelle (OLTP, 3NF)

L'OLTP capture la réalité métier au grain transactionnel. On y privilégie
l'intégrité référentielle et la non-redondance.

### 1.1 Sous-domaines

| Sous-domaine     | Tables principales                                                                                |
|------------------|---------------------------------------------------------------------------------------------------|
| Géographie       | `continent`, `country`, `region`, `city`                                                          |
| Organisation RH  | `org_country`, `org_company`, `org_department`, `org_section`, `org_group`                        |
| Employés         | `employee` (auto-référence pour le manager), `employee_contract`                                  |
| Produits         | `product_line`, `product_category`, `product_group`, `product`, `product_price_history`, `product_discount` |
| Fournisseurs     | `supplier`                                                                                        |
| Clients          | `customer_group`, `customer`, `loyalty_card`                                                      |
| Canaux           | `sales_channel` (STORE / CATALOG / INTERNET)                                                      |
| Commandes        | `sales_order`, `sales_order_line`                                                                 |

### 1.2 Choix structurants

- **Hiérarchie produit** matérialisée par 4 tables (Ligne → Catégorie → Groupe → Produit).
- **Hiérarchie organisationnelle** matérialisée par 5 tables (Pays → Compagnie → Département → Section → Groupe).
- **Historique de prix** : table `product_price_history(start_date, end_date, cost, sale_price)` ;
  une ligne courante a `end_date IS NULL`. Permet de retrouver le prix appliqué au moment de
  la commande.
- **Remises** : `product_discount` avec période de validité explicite.
- **Carte de fidélité** : table dédiée `loyalty_card` 1-1 optionnelle avec `customer`.
- **Manager hiérarchique** : auto-référence `employee.manager_id`.
- **Canaux de vente** : table de référence (3 lignes), évite l'enum.
- **Devise** : tous les montants sont stockés en USD (cf. énoncé).

---

## 2. Transition OLTP → modélisation dimensionnelle

Cette section formalise **comment** le schéma 3NF a été dérivé en schéma en étoile.
On suit la méthode **Kimball en 4 étapes** (Kimball & Ross, *The Data Warehouse Toolkit*).

### 2.1 Étape 1 — Identifier le processus métier

Le processus métier au cœur des questions analytiques (énoncé p. 3) est :
> **« Vendre un article à un client, via un canal donné, par un commercial donné, à une date donnée. »**

C'est ce processus qui produit la mesure principale (chiffre d'affaires) et qui sera
matérialisé par la table de faits.

### 2.2 Étape 2 — Choisir le grain

Choix structurant. Trois grains candidats :

| Grain candidat        | Pour                                  | Contre                                                    |
|-----------------------|---------------------------------------|-----------------------------------------------------------|
| Commande complète     | Volume modeste                        | Perd la dimension produit                                 |
| Ligne de commande ✅  | Conserve le détail produit            | Volume = ~980 000 lignes (acceptable)                     |
| Ligne consolidée jour | Très petit volume                     | Perd commande, client précis, canal individuel            |

Le grain retenu est **la ligne de commande** (`sales_order_line`). Toutes les mesures
de la fact seront additives au niveau ligne.

### 2.3 Étape 3 — Identifier les dimensions

À partir des questions analytiques, on identifie 7 dimensions :

| Question analytique (énoncé)                       | Dimension associée                          |
|----------------------------------------------------|---------------------------------------------|
| « Quels produits se vendent le mieux ? »           | `dim_product`                               |
| « par pays et année donnés »                       | `dim_geography` + `dim_date`                |
| « marge par groupe de produit »                    | `dim_product` (hiérarchie aplatie)          |
| « commerciaux par sexe, âge, salaire, pays »       | `dim_employee` (avec attributs RH)          |
| « groupes de clients identifiés »                  | `dim_customer` (groupe + démographie)       |
| « fournisseurs proposant des produits rentables »  | `dim_supplier`                              |
| « moyens-commerciaux H/F »                         | `dim_employee.gender`                       |

À cela s'ajoute `dim_channel` (STORE / CATALOG / INTERNET) — directement utile pour
les analyses de canal.

#### 2.3.1 Aplatissement des hiérarchies

Les hiérarchies OLTP **normalisées** sont **aplaties** dans la dimension.
Exemple produit (4 tables → 1 dimension) :

```
ops.product_line ─┐
ops.product_category ─┐
ops.product_group ─┐
ops.product ───────┴──────► dim_product
                   (attributs : product_name, product_group_name,
                    product_category_name, product_line_name,
                    supplier_name)
```

Idem pour la géographie (4 tables → 1 dimension) et l'organisation RH (5 tables →
attributs aplatis dans `dim_employee`). Cela permet :
- Des **drill-down** rapides en SQL (`GROUP BY product_line_name`,
  `GROUP BY product_group_name`, …).
- Une **lisibilité** accrue pour les outils de BI.
- Un coût en redondance assumé — c'est l'objet d'un DWH.

#### 2.3.2 Surrogate keys

Chaque dimension porte une **clé technique** (surrogate key) générée à
l'insertion : `product_key`, `customer_key`, `employee_key`, etc. La clé naturelle
OLTP est conservée comme attribut (`product_id`, `customer_id`, ...) pour la
traçabilité, mais **n'est jamais utilisée comme FK dans `fact_sales`**.

Justifications :
- Découple le DWH des changements OLTP (renommage, fusion, ré-attribution d'IDs).
- Indispensable pour SCD2 : plusieurs versions d'un client ont le même
  `customer_id` mais des `customer_key` différents.

### 2.4 Étape 4 — Identifier les faits

Les **mesures** sont calculées à partir de la ligne de commande :

| Mesure DWH         | Source OLTP                                          | Type                |
|--------------------|------------------------------------------------------|---------------------|
| `quantity`         | `sales_order_line.quantity`                          | additive            |
| `unit_price`       | `sales_order_line.unit_price`                        | non additive        |
| `unit_cost`        | `sales_order_line.unit_cost`                         | non additive        |
| `discount_pct`     | `sales_order_line.discount_pct`                      | non additive        |
| `gross_amount`     | `quantity × unit_price`                              | **additive**        |
| `discount_amount`  | `gross_amount × discount_pct`                        | **additive**        |
| `net_amount`       | `gross_amount − discount_amount`                     | **additive (CA)**   |
| `cost_amount`      | `quantity × unit_cost`                               | **additive**        |
| `margin_amount`    | `net_amount − cost_amount`                           | **additive (marge)**|

Les mesures dérivées sont **pré-calculées et matérialisées** dans `fact_sales` :
- évite les recalculs à la volée → meilleure performance ;
- garantit qu'analystes et rapports parlent du même CA / de la même marge.

#### 2.4.1 Degenerate dimensions

`order_id` et `line_no` sont conservés dans `fact_sales` sans table dimensionnelle
associée — ce sont des **degenerate dimensions** : utiles pour le drill-down jusqu'à
la commande individuelle, mais sans attribut propre à porter dans une table.

### 2.5 Bus matrix (synthèse)

| Processus métier   | dim_date | dim_product | dim_customer | dim_employee | dim_supplier | dim_channel | dim_geography |
|--------------------|:--------:|:-----------:|:------------:|:------------:|:------------:|:-----------:|:-------------:|
| Vente (ligne)      | ✅       | ✅          | ✅           | ✅           | ✅           | ✅          | ✅ (client)   |

Une seule ligne aujourd'hui — l'extension naturelle pour des phases ultérieures
ajouterait *Réception fournisseur* et *Mouvement de stock*, qui partageraient
`dim_product`, `dim_supplier`, `dim_date`, `dim_geography`.

### 2.6 SCD (Slowly Changing Dimensions)

| Dimension     | Type SCD | Justification                                                  |
|---------------|----------|----------------------------------------------------------------|
| dim_date      | n/a      | statique                                                       |
| dim_product   | SCD1     | nom et hiérarchie peu volatiles, on écrase                     |
| dim_customer  | SCD2     | groupe d'achat évolue, on veut analyser les ventes « à l'époque »|
| dim_employee  | SCD2     | salaire, section, manager évoluent (RH demande la traçabilité) |
| dim_supplier  | SCD1     | rare changement                                                |
| dim_channel   | SCD1     | référentiel quasi-statique                                     |
| dim_geography | SCD1     | référentiel                                                    |

**Implémentation SCD2** : colonnes `effective_from`, `effective_to`, `is_current`,
`row_hash`. Une nouvelle version est créée si `row_hash` (SHA-256 sur les attributs
suivis) diffère.

### 2.7 Synthèse de la transition

```
OLTP (3NF · ops)                       ETL (T-SQL · OrionETL)              DWH (étoile · dw)
─────────────────                      ─────────────────────                ─────────────────
ops.product_line   ┐                                                       
ops.product_category│ aplatit          dim.dim_product (SCD1)               dw.dim_product
ops.product_group  ├─────────────────► (full reload)                       
ops.product        ┘                                                       
ops.supplier                          dim.dim_supplier (SCD1)               dw.dim_supplier
ops.customer + group + city + region… dim.dim_customer (SCD2)               dw.dim_customer
ops.employee + org_* + city + manager dim.dim_employee (SCD2)               dw.dim_employee
ops.continent/country/region/city    dim.dim_geography (SCD1)              dw.dim_geography
ops.sales_channel                    dim.dim_channel  (SCD1)               dw.dim_channel
(date series 1997-2003)              dim.dim_date     (statique)           dw.dim_date
ops.sales_order + sales_order_line   fact.fact_sales (incr. + mesures)     dw.fact_sales
                                     etl.watermark, etl.run_log            (méta)
```

---

## 3. Modélisation dimensionnelle (DWH, schéma en étoile)

L'entrepôt est un **modèle en étoile** centré sur la table de faits `fact_sales`
(grain = ligne de commande), entouré de 7 dimensions conformes.

### 3.1 Table de faits

| Colonne              | Type      | Rôle                                                       |
|----------------------|-----------|------------------------------------------------------------|
| `date_key`           | INT       | FK `dim_date` (jour de la commande)                        |
| `product_key`        | BIGINT    | FK `dim_product` (SCD1)                                    |
| `customer_key`       | BIGINT    | FK `dim_customer` (SCD2)                                   |
| `employee_key`       | BIGINT    | FK `dim_employee` (SCD2)                                   |
| `supplier_key`       | BIGINT    | FK `dim_supplier`                                          |
| `channel_key`        | INT       | FK `dim_channel`                                           |
| `geography_cust_key` | BIGINT    | FK `dim_geography` (lieu du client)                        |
| `order_id`           | BIGINT    | clé naturelle (DD = degenerate dimension)                  |
| `line_no`            | SMALLINT  | numéro de ligne (DD)                                       |
| `quantity`           | NUMERIC   | mesure additive                                            |
| `unit_price`         | NUMERIC   | mesure non-additive                                        |
| `unit_cost`          | NUMERIC   | mesure non-additive                                        |
| `discount_pct`       | NUMERIC   | mesure non-additive                                        |
| `gross_amount`       | NUMERIC   | quantity × unit_price                                      |
| `discount_amount`    | NUMERIC   | gross × discount_pct                                       |
| `net_amount`         | NUMERIC   | **chiffre d'affaires** = gross − discount                  |
| `cost_amount`        | NUMERIC   | quantity × unit_cost                                       |
| `margin_amount`      | NUMERIC   | net − cost (mesure additive)                               |

### 3.2 Dimensions

- **`dim_date`** : générée pour 1997-01-01 → 2003-12-31. Attributs : jour, mois,
  trimestre, année, jour de la semaine, week-end, saison, libellé mois.
- **`dim_product`** (SCD1) : product_id, nom, groupe, catégorie, ligne, supplier_id_natural,
  supplier_name. Hiérarchie aplatie.
- **`dim_customer`** (SCD2) : groupe client, sexe, tranche d'âge, has_loyalty_card,
  ville/pays/continent. SCD2 pour suivre les changements de groupe ou d'adresse.
- **`dim_employee`** (SCD2) : nom, sexe, tranche d'âge, salaire, tranche de salaire,
  pays/compagnie/département/section/groupe, manager_name, hire_date.
- **`dim_supplier`** : nom, pays, continent.
- **`dim_channel`** : code, libellé.
- **`dim_geography`** : ville, région, pays, continent.

---

## 4. ETL : SQL Server + orchestrateur

### 4.1 Architecture en deux niveaux

L'énoncé du TP impose la mise en place d'un processus ETL — Orion l'implémente
en **deux niveaux complémentaires** :

| Couche                        | Rôle                                                       | Technologie     |
|-------------------------------|------------------------------------------------------------|-----------------|
| Logique de transformation     | TRUNCATE/INSERT/MERGE, calcul SCD2, calcul mesures, log    | **SQL Server T-SQL** (procédures stockées) |
| Transport / orchestration     | Extract Postgres OLTP, push staging SQL Server, EXEC procs, pull SQL Server, COPY DWH | Python (orchestrate.py + APScheduler) |

Toute la **logique métier ETL** est concentrée dans des procédures stockées
T-SQL — elles sont versionnées, testables individuellement (`EXEC etl.sp_load_dim_customer`),
journalisées dans `etl.run_log`. L'orchestrateur Python est un **transporteur**
neutre, sans logique de transformation.

### 4.2 Procédures stockées T-SQL (zone *gold* SQL Server)

| Procédure                       | Fréquence       | Mode                  |
|---------------------------------|-----------------|-----------------------|
| `etl.sp_load_dim_date`          | une fois        | bootstrap (idempotent)|
| `etl.sp_load_dim_channel`       | quotidien       | full reload           |
| `etl.sp_load_dim_geography`     | quotidien       | full reload           |
| `etl.sp_load_dim_supplier`      | quotidien       | full reload           |
| `etl.sp_load_dim_product`       | quotidien       | full reload (SCD1)    |
| `etl.sp_load_dim_customer`      | quotidien       | **SCD2 merge**        |
| `etl.sp_load_dim_employee`      | quotidien       | **SCD2 merge**        |
| `etl.sp_load_fact_sales`        | quotidien       | **incrémental** (watermark) |
| `etl.sp_run_pipeline`           | quotidien       | enchaînement complet  |

Le **watermark** est stocké dans `etl.watermark(job_name, last_value)` côté SQL
Server. Pour `fact_sales`, c'est `MAX(order_date)` traitée.

### 4.3 Pipeline d'un run

1. **Extract** (orchestrateur) : 7 SELECTs dénormalisés sur Postgres OLTP.
2. **Land** (orchestrateur) : `TRUNCATE staging.*` + `INSERT executemany` côté SQL Server.
3. **Transform** (T-SQL) : `EXEC etl.sp_run_pipeline` enchaîne dim_*, SCD2, fact_sales,
   et journalise dans `etl.run_log`.
4. **Push** (orchestrateur) : `SELECT` depuis `dim.*` / `fact.*` côté SQL Server, puis
   `COPY` dans Postgres DWH (`dw.*`).

Cette séparation rend visible chacune des trois zones d'un DWH (bronze/silver/gold)
sans cérémonie supplémentaire :
- **bronze** = `ops.*` (Postgres OLTP, brut)
- **silver** = `staging.*` (SQL Server, après extract simple)
- **gold** = `dim.*` + `fact.*` (SQL Server) puis `dw.*` (Postgres DWH, exposé aux analystes)

### 4.4 Alternative *« tout SQL Server »*

Pour information : la même architecture peut être réalisée en **pur T-SQL** via un
**Linked Server** PostgreSQL (driver ODBC `psqlodbc` installé dans le container
`mssql-etl`). Les procédures utiliseraient `OPENQUERY(ORION_OLTP_LINK, '…')` pour
lire OLTP et `INSERT … SELECT * FROM OPENQUERY(...)` pour écrire DWH. Cette
variante a été écartée pour le TP car :
- la configuration ODBC dans un container Linux est plus fragile ;
- l'orchestrateur Python permet un journal Python lisible (`docker compose logs`)
  et facilite les tests ponctuels d'extraction.

---

## 5. Stack Docker

- `postgres-oltp` : base opérationnelle Postgres (port 5433).
- `postgres-dwh`  : entrepôt Postgres (port 5434).
- `mssql-etl`     : SQL Server 2022 hébergeant les procédures T-SQL (port 1433).
- `orchestrator`  : conteneur Python long-running avec APScheduler.
- `data-gen`      : conteneur one-shot Python qui peuple l'OLTP via Faker.
- `adminer`      : UI web unique (Adminer 5) pour Postgres OLTP, Postgres
  DWH **et** SQL Server (port 8080). Trois cibles pré-configurées dans
  `adminer/index.php`.

Le réseau Docker `orion-net` isole les communications inter-services. Trois
volumes persistent les données : `oltp_data`, `dwh_data`, `mssql_data`
(Adminer est sans état).
