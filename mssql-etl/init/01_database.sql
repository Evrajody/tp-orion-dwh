-- ============================================================================
--  01 — Création de la base OrionETL et des schémas (idempotent)
-- ============================================================================
SET NOCOUNT ON;

IF DB_ID(N'OrionETL') IS NULL
BEGIN
    PRINT '[01] Création de la base OrionETL';
    CREATE DATABASE OrionETL;
END
ELSE
    PRINT '[01] Base OrionETL déjà présente';
GO

USE OrionETL;
GO

IF SCHEMA_ID(N'staging') IS NULL EXEC('CREATE SCHEMA staging');
IF SCHEMA_ID(N'etl')     IS NULL EXEC('CREATE SCHEMA etl');
IF SCHEMA_ID(N'dim')     IS NULL EXEC('CREATE SCHEMA dim');
IF SCHEMA_ID(N'fact')    IS NULL EXEC('CREATE SCHEMA fact');
GO

PRINT '[01] Schémas staging, etl, dim, fact prêts.';
GO
