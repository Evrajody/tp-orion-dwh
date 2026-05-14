-- ============================================================================
--  12 - Migration CHAR(n) -> NCHAR(n) sur les tables SQL Server
--
--  CONTEXTE
--  --------
--  Les flux SSIS lisent l'OLTP Postgres via le pilote psqlODBC. Ce pilote
--  remonte toutes les colonnes texte en Unicode (SSIS type DT_WSTR).
--  Les colonnes cibles cote SQL Server etaient en CHAR(n) (SSIS type DT_STR,
--  non-Unicode). Resultat : erreur a la validation de la Destination OLE DB
--    "column XXX cannot convert between unicode and non unicode data types".
--
--  CORRECTIF
--  ---------
--  On passe toutes les colonnes CHAR(n) impactees en NCHAR(n). Les donnees
--  concernees (code_pays ISO-3166, sexe M/F, hash hex SHA-256) sont purement
--  ASCII : pas de surcout de stockage significatif, pas de perte.
--
--  PORTEE
--  ------
--  3 zones a modifier :
--    1. OrionETL.staging.*    (3 colonnes : code_pays, sexe x2)
--    2. OrionETL.dim.*        (5 colonnes : code_pays, sexe x2, hash_ligne x2)
--    3. OrionDWH.dw.*         (5 colonnes : code_pays, sexe x2, hash_ligne x2)
--
--  EXECUTION
--  ---------
--  Lancer ce script dans SSMS connecte en sysadmin. Les ALTER COLUMN
--  reecrivent uniquement la metadata + recodent les pages : negligeable
--  sur des tables Orion (quelques milliers a quelques millions de lignes).
--  Aucune perte de donnees, l'operation est reversible (NCHAR(n) -> CHAR(n)
--  fonctionnerait dans l'autre sens si les donnees restent ASCII).
--
--  Apres execution, rafraichir les metadonnees dans SSDT :
--    - DFT impacte -> double-clic Destination OLE DB -> onglet Mappages
--    - Si fleche rouge persiste : Editeur avance -> Refresh
-- ============================================================================


-- --------------------------------------------------------------------------
-- 1) OrionETL.staging.*
--    Tables d'atterrissage des flux ODBC depuis Postgres.
--    Toutes les colonnes texte arrivent en wstr -> tout passer en NCHAR.
-- --------------------------------------------------------------------------
USE OrionETL;
GO

-- staging.geographie_full : code_pays = code ISO-3166-1 alpha-2 ('FR','US',...)
ALTER TABLE staging.geographie_full ALTER COLUMN code_pays NCHAR(2) NOT NULL;
GO

-- staging.client_full : sexe = 'M' ou 'F' (nullable, certains clients
-- n'ont pas declare leur sexe dans l'OLTP)
ALTER TABLE staging.client_full     ALTER COLUMN sexe      NCHAR(1) NULL;
GO

-- staging.employe_full : sexe = 'M' ou 'F' (obligatoire RH)
ALTER TABLE staging.employe_full    ALTER COLUMN sexe      NCHAR(1) NOT NULL;
GO


-- --------------------------------------------------------------------------
-- 2) OrionETL.dim.*
--    Tables dimensionnelles intermediaires (zone "gold" transitoire).
--    Alimentees par les procedures stockees etl.sp_load_dim_* qui lisent
--    le staging et produisent les colonnes SCD2 (effectif_du, est_courant,
--    hash_ligne). Le hash_ligne est un SHA-256 hex = 64 caracteres ASCII.
-- --------------------------------------------------------------------------
USE OrionETL;
GO

-- dim.dim_geographie : code_pays ISO-3166-1 alpha-2
ALTER TABLE dim.dim_geographie ALTER COLUMN code_pays  NCHAR(2)  NOT NULL;
GO

-- dim.dim_client : sexe + hash_ligne SCD2
ALTER TABLE dim.dim_client     ALTER COLUMN sexe       NCHAR(1)  NULL;
GO
ALTER TABLE dim.dim_client     ALTER COLUMN hash_ligne NCHAR(64) NOT NULL;
GO

-- dim.dim_employe : sexe + hash_ligne SCD2
ALTER TABLE dim.dim_employe    ALTER COLUMN sexe       NCHAR(1)  NOT NULL;
GO
ALTER TABLE dim.dim_employe    ALTER COLUMN hash_ligne NCHAR(64) NOT NULL;
GO


-- --------------------------------------------------------------------------
-- 3) OrionDWH.dw.*
--    Schema en etoile de presentation. Les DFT_DWH_* copient depuis
--    OrionETL.dim.* (deja NCHAR apres etape 2 ci-dessus) -> il faut que
--    la destination DWH soit aussi NCHAR pour eviter le re-collapse en str.
-- --------------------------------------------------------------------------
USE OrionDWH;
GO

-- dw.dim_geographie : code_pays ISO-3166-1
ALTER TABLE dw.dim_geographie ALTER COLUMN code_pays  NCHAR(2)  NOT NULL;
GO

-- dw.dim_client : sexe + hash_ligne
ALTER TABLE dw.dim_client     ALTER COLUMN sexe       NCHAR(1)  NULL;
GO
ALTER TABLE dw.dim_client     ALTER COLUMN hash_ligne NCHAR(64) NOT NULL;
GO

-- dw.dim_employe : sexe + hash_ligne
ALTER TABLE dw.dim_employe    ALTER COLUMN sexe       NCHAR(1)  NOT NULL;
GO
ALTER TABLE dw.dim_employe    ALTER COLUMN hash_ligne NCHAR(64) NOT NULL;
GO


-- --------------------------------------------------------------------------
-- 4) Verification finale
--    Doit retourner 13 lignes, toutes avec system_type_name LIKE 'nchar%'.
-- --------------------------------------------------------------------------
USE OrionETL;
GO
SELECT
    DB_NAME()                       AS base,
    OBJECT_SCHEMA_NAME(c.object_id) AS schema_nom,
    OBJECT_NAME(c.object_id)        AS table_nom,
    c.name                          AS colonne_nom,
    t.name + '(' + CAST(c.max_length / 2 AS VARCHAR(5)) + ')' AS type_actuel
FROM sys.columns c
JOIN sys.types   t ON t.user_type_id = c.user_type_id
WHERE c.name IN ('code_pays','sexe','hash_ligne')
  AND OBJECT_SCHEMA_NAME(c.object_id) IN ('staging','dim');
GO

USE OrionDWH;
GO
SELECT
    DB_NAME()                       AS base,
    OBJECT_SCHEMA_NAME(c.object_id) AS schema_nom,
    OBJECT_NAME(c.object_id)        AS table_nom,
    c.name                          AS colonne_nom,
    t.name + '(' + CAST(c.max_length / 2 AS VARCHAR(5)) + ')' AS type_actuel
FROM sys.columns c
JOIN sys.types   t ON t.user_type_id = c.user_type_id
WHERE c.name IN ('code_pays','sexe','hash_ligne')
  AND OBJECT_SCHEMA_NAME(c.object_id) = 'dw';
GO


-- ============================================================================
--  FIN. Si toutes les lignes verifient type_actuel LIKE 'nchar%' :
--    - Revenir dans SSDT
--    - DFT_Staging_Geographie -> double-clic Destination OLE DB
--    - Onglet Mappages : la fleche rouge sur code_pays doit avoir disparu
--    - Repeter pour les autres DFT impactes : Client, Employe (sexe),
--      DimClient/DimEmploye (sexe + hash_ligne)
-- ============================================================================
