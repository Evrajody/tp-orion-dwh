# SSIS — Orion_Pipeline_Quotidien.dtsx

Package SSIS complet (full-fidelity) reproduisant le pipeline ETL Orion :
extraction Postgres OLTP via ODBC, chargement staging SQL Server,
appel des procédures stockées T-SQL, export vers DWH.

## Fichiers

- `generate_dtsx.py` — générateur Python. Modifier les listes `STAGING_DFTS`
  et `DWH_DFTS` puis relancer pour régénérer le `.dtsx`.
- `Orion_Pipeline_Quotidien.dtsx` — package SSIS importable (généré).

## Contenu du package

| Élément | Détail |
|---|---|
| 3 Connection Managers (niveau package) | `ORION_PG_OLTP_CM` (ODBC, DSN `ORION_PG_OLTP`), `OrionETL_CM` et `OrionDWH_CM` (OLE DB, `localhost`, Windows Auth) |
| 3 Variables (`User::`) | `Watermark` (DateTime), `LignesIn` (Int64), `LignesOut` (Int64) |
| 4 Execute SQL Task | `SQL_Lire_Watermark`, `SQL_Truncate_Staging`, `SQL_Exec_sp_run_pipeline`, `SQL_Truncate_DWH` |
| 3 Sequence Containers | `SEQ_Pipeline_Complet` qui contient `SEQ_Chargement_Staging` et `SEQ_Push_DWH` |
| 7 DFT Staging | Geographie, Fournisseur, Canal, Produit, Client, Employe, Lignes_Commande (incrémental, paramètre `User::Watermark`) |
| 8 DFT DWH | DimDate, DimCanal, DimGeographie, DimFournisseur, DimProduit, DimClient, DimEmploye, FaitVentes |
| Précédences | 33 contraintes, dont `Logical AND` aux convergences `Lignes_Commande` et `FaitVentes` |

Chaque DFT contient :
- une Source (ODBC depuis `ORION_PG_OLTP_CM` côté staging, OLE DB depuis
  `OrionETL_CM` côté DWH) en mode `SqlCommand` avec la requête déjà saisie ;
- une Destination OLE DB en mode `Table or view - fast load` ;
- les métadonnées de colonnes (nom, type, longueur, précision, scale,
  code page) hardcodées d'après les schémas du dépôt.

## Prérequis SSDT

1. Visual Studio 2022 avec extension **SQL Server Integration Services
   Projects** installée.
2. DSN système **`ORION_PG_OLTP`** créé via `Sources de données ODBC
   (64 bits)` — cf. étape 4 de `doc/rapport/migration-windows-sqlserver.tex`.
3. Bases **`OrionETL`** et **`OrionDWH`** créées sur l'instance `localhost`,
   avec les schémas peuplés par `mssql-etl/init/*.sql` et
   `sqlserver-migration-scripts/`.

## Import dans SSDT

1. **Créer un projet vide** : Visual Studio → `Fichier` → `Nouveau` →
   `Projet…` → filtrer "Integration Services" → `Integration Services
   Project` → nommer `Orion_ETL`.

2. **Supprimer le package par défaut** : dans `Explorateur de solutions`,
   clic droit sur `Package.dtsx` → `Supprimer` (et confirmer la suppression
   du fichier).

3. **Importer le `.dtsx`** : clic droit sur le dossier `Packages SSIS` →
   `Ajouter un package existant` → `Système de fichiers` → parcourir vers
   `ssis/Orion_Pipeline_Quotidien.dtsx` → `OK`.

4. **Première ouverture** : double-cliquer le package. SSDT valide les
   Connection Managers (peut afficher des avertissements jaunes — c'est
   normal tant que tu n'as pas testé les CMs).

5. **Tester les Connection Managers** : dans la zone basse
   `Gestionnaires de connexions`, clic droit sur chaque CM → `Tester la
   connexion`. Les 3 doivent répondre OK. Si non :
   - `ORION_PG_OLTP_CM` : vérifier que le DSN existe en
     `Sources de données ODBC (64 bits)`.
   - `OrionETL_CM` / `OrionDWH_CM` : vérifier que les bases existent
     (sinon les créer via `mssql-etl/init/01_database.sql`).

6. **Rafraîchir les métadonnées des composants** (recommandé) : pour
   chaque DFT, double-cliquer la `ODBC Source` (ou `OLE DB Source`),
   onglet `Colonnes`, cliquer `OK` (SSDT recharge les colonnes depuis
   la base réelle, ce qui aligne les types). Idem pour la `OLE DB
   Destination` → onglet `Mappages` → `OK`. Si tu vois des flèches rouges
   d'inadéquation de type, c'est qu'une colonne du schéma a divergé
   du code généré : ajuster `generate_dtsx.py` et régénérer.

7. **Build** : `Générer` → `Générer la solution`. Le `.ispac` est
   produit dans `bin\Development\`.

## Exécution

### Depuis SSDT (test)

Clic droit sur le package → `Exécuter le package`. Le canvas s'anime
(jaune en cours, vert quand réussi). Vérifier `User::Watermark` dans
le panneau `Locals` après `SQL_Lire_Watermark`.

### Déploiement sur SSISDB

Clic droit sur le projet `Orion_ETL` → `Déployer` → assistant qui
demande serveur et chemin (cf. étape 30 du rapport).

### Planification

Travail SQL Server Agent référençant le package dans le catalogue
(cf. étape 33 du rapport).

## Limitations connues

- **Niveau package, pas projet** : les CMs sont dans le `.dtsx`, pas dans
  des fichiers `.conmgr` séparés. Pour migrer vers du projet-level,
  glisser-déposer chaque CM depuis l'onglet `Gestionnaires de connexions`
  vers `Gestionnaires de connexions (projet)` dans l'`Explorateur de
  solutions`.
- **Pas de Project.params** : les paramètres `p_LoadDate`, `p_BatchSize`,
  `p_RunOnEmptyOLTP` mentionnés dans le rapport sont à recréer manuellement
  dans `Project.params` une fois le package importé. Les valeurs par
  défaut sont actuellement hardcodées dans le SQL des Execute SQL Task.
- **Pas de Logical AND visible** : dans le XML, les précédences vers
  `Lignes_Commande` et `FaitVentes` sont marquées `DTS:LogicalAnd="True"`,
  mais SSDT peut afficher pointillé/solide selon ta version — vérifier
  visuellement et reconfigurer via clic droit sur la flèche →
  `Éditer la contrainte de précédence` si besoin.
- **Code page par défaut 1252** sur OLE DB Source/Destination : les
  colonnes `CHAR(n)` SQL Server arrivent en `DT_STR` (Latin-1). Si ta
  base utilise une collation autre que Latin1, ajuster `DefaultCodePage`
  dans le générateur.
- **Première validation peut afficher des warnings** : c'est normal tant
  que les composants n'ont pas été ouverts une fois dans SSDT pour
  rafraîchir leurs métadonnées contre les bases vivantes.

## Régénération

```bash
cd ssis
python3 generate_dtsx.py
# -> Orion_Pipeline_Quotidien.dtsx réécrit
```

Le générateur utilise `uuid5` sur un namespace fixe : les GUIDs sont
**reproductibles** d'une exécution à l'autre. Modifier une requête SQL
ne casse pas les autres DFTs ; modifier la structure d'un DFT (renommage,
ajout de colonne) régénère uniquement les GUIDs concernés.
