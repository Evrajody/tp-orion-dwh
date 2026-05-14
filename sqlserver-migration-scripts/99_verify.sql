-- ============================================================================
-- 99 -- Requetes de verification de l'installation et de l'execution ETL.
-- A executer dans : master (le script bascule lui-meme avec USE)
-- A lancer        : apres chaque etape pour controler, et apres un run complet.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Bases creees ?
-- ----------------------------------------------------------------------------
PRINT '--- 1. Bases creees ---';
SELECT name, state_desc, recovery_model_desc, collation_name
  FROM sys.databases
 WHERE name IN ('OrionOLTP','OrionETL','OrionDWH');
-- Resultat attendu : 3 lignes en ONLINE / SIMPLE / French_CI_AS

-- ----------------------------------------------------------------------------
-- 2. Schemas et tables OrionOLTP
-- ----------------------------------------------------------------------------
USE OrionOLTP;
GO
PRINT '--- 2. Tables OrionOLTP (schema ops) ---';
SELECT t.name AS table_name,
       p.rows AS row_count
  FROM sys.tables t
  JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
 WHERE t.schema_id = SCHEMA_ID('ops')
 ORDER BY t.name;
-- Apres script 03, les donnees de reference doivent avoir des row_count > 0

-- ----------------------------------------------------------------------------
-- 3. Schemas et tables OrionETL
-- ----------------------------------------------------------------------------
USE OrionETL;
GO
PRINT '--- 3. Tables OrionETL ---';
SELECT s.name AS schema_name,
       t.name AS table_name,
       p.rows AS row_count
  FROM sys.tables t
  JOIN sys.schemas s ON s.schema_id = t.schema_id
  JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
 WHERE s.name IN ('etl','staging','dim','fact')
 ORDER BY s.name, t.name;

PRINT '--- 3.b Procedures stockees etl.* ---';
SELECT name, create_date, modify_date
  FROM sys.procedures
 WHERE schema_id = SCHEMA_ID('etl')
 ORDER BY name;
-- Resultat attendu :
-- sp_charger_staging, sp_load_dim_canal, sp_load_dim_client, sp_load_dim_date,
-- sp_load_dim_employe, sp_load_dim_fournisseur, sp_load_dim_geographie,
-- sp_load_dim_produit, sp_load_fait_ventes, sp_pousser_dwh, sp_run_complet,
-- sp_run_end, sp_run_pipeline, sp_run_start

-- ----------------------------------------------------------------------------
-- 4. Schemas et tables OrionDWH
-- ----------------------------------------------------------------------------
USE OrionDWH;
GO
PRINT '--- 4. Tables OrionDWH (schema dw) ---';
SELECT t.name AS table_name,
       p.rows AS row_count
  FROM sys.tables t
  JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
 WHERE t.schema_id = SCHEMA_ID('dw')
 ORDER BY t.name;

-- ----------------------------------------------------------------------------
-- 5. Apres un run ETL : journal d'execution
-- ----------------------------------------------------------------------------
USE OrionETL;
GO
PRINT '--- 5. Journal des 20 derniers runs ETL ---';
SELECT TOP 20 run_id, job_name, started_at, ended_at, status,
              rows_in, rows_out,
              DATEDIFF(SECOND, started_at, ended_at) AS duree_sec,
              error_msg
  FROM etl.run_log
 ORDER BY run_id DESC;
-- Resultat attendu : tous en status='SUCCESS', error_msg NULL

-- ----------------------------------------------------------------------------
-- 6. Verifier la coherence DWH (nombres de lignes)
-- ----------------------------------------------------------------------------
USE OrionDWH;
GO
PRINT '--- 6. Volumes DWH ---';
SELECT 'dim_date'        AS table_name, COUNT(*) AS nb FROM dw.dim_date
UNION ALL SELECT 'dim_canal',         COUNT(*) FROM dw.dim_canal
UNION ALL SELECT 'dim_geographie',    COUNT(*) FROM dw.dim_geographie
UNION ALL SELECT 'dim_fournisseur',   COUNT(*) FROM dw.dim_fournisseur
UNION ALL SELECT 'dim_produit',       COUNT(*) FROM dw.dim_produit
UNION ALL SELECT 'dim_client',        COUNT(*) FROM dw.dim_client
UNION ALL SELECT 'dim_employe',       COUNT(*) FROM dw.dim_employe
UNION ALL SELECT 'fait_ventes',       COUNT(*) FROM dw.fait_ventes;

-- ----------------------------------------------------------------------------
-- 7. Verifier les 5 colonnes contrat dans dim_employe
-- ----------------------------------------------------------------------------
PRINT '--- 7. Repartition des types de contrat dans dim_employe ---';
SELECT type_contrat_courant, statut_contrat,
       COUNT(*) AS nb_employes,
       AVG(salaire) AS salaire_moyen,
       AVG(CAST(nb_contrats_signes AS DECIMAL(10,2))) AS nb_contrats_moy
  FROM dw.dim_employe
 WHERE est_courant = 1
 GROUP BY type_contrat_courant, statut_contrat
 ORDER BY type_contrat_courant, statut_contrat;
-- Resultat attendu : repartition CDI/CDD/Stage/Alternance/Interim/Freelance/SansContrat

-- ----------------------------------------------------------------------------
-- 8. Test rapide -- 1 question analytique de l'enonce
-- ----------------------------------------------------------------------------
PRINT '--- 8. Top 10 commerciaux par chiffre d''affaires ---';
SELECT TOP 10
       de.nom_complet,
       de.org_pays,
       de.sexe,
       de.tranche_age,
       de.tranche_salaire,
       de.type_contrat_courant,
       SUM(f.montant_net)     AS ca_total,
       SUM(f.montant_marge)   AS marge_totale,
       COUNT(*)               AS nb_lignes_vendues
  FROM dw.fait_ventes f
  JOIN dw.dim_employe de ON de.cle_employe = f.cle_employe
 WHERE de.est_courant = 1
 GROUP BY de.nom_complet, de.org_pays, de.sexe, de.tranche_age,
          de.tranche_salaire, de.type_contrat_courant
 ORDER BY ca_total DESC;
GO
