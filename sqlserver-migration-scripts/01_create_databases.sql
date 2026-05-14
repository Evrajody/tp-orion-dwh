-- ============================================================================
-- 01 -- Creation des 3 bases Orion sur l'instance SQL Server locale.
-- A executer dans : master
-- Pre-requis      : aucun (premier script).
-- Verification    : SELECT name FROM sys.databases
--                   WHERE name IN ('OrionOLTP','OrionETL','OrionDWH');
-- ============================================================================
USE master;
GO

IF DB_ID('OrionOLTP') IS NULL
BEGIN
    PRINT '[01] Creation de OrionOLTP';
    CREATE DATABASE OrionOLTP COLLATE French_CI_AS;
END
ELSE PRINT '[01] OrionOLTP existe deja';
GO

IF DB_ID('OrionETL') IS NULL
BEGIN
    PRINT '[01] Creation de OrionETL';
    CREATE DATABASE OrionETL COLLATE French_CI_AS;
END
ELSE PRINT '[01] OrionETL existe deja';
GO

IF DB_ID('OrionDWH') IS NULL
BEGIN
    PRINT '[01] Creation de OrionDWH';
    CREATE DATABASE OrionDWH COLLATE French_CI_AS;
END
ELSE PRINT '[01] OrionDWH existe deja';
GO

-- Modele de recuperation SIMPLE : adapte aux charges ETL massives,
-- pas besoin de point-in-time recovery sur un TP.
ALTER DATABASE OrionOLTP SET RECOVERY SIMPLE;
ALTER DATABASE OrionETL  SET RECOVERY SIMPLE;
ALTER DATABASE OrionDWH  SET RECOVERY SIMPLE;
GO

-- Schemas dans OrionETL (4 schemas distincts pour la zone silver+gold)
USE OrionETL;
GO
IF SCHEMA_ID('staging') IS NULL EXEC('CREATE SCHEMA staging');
IF SCHEMA_ID('etl')     IS NULL EXEC('CREATE SCHEMA etl');
IF SCHEMA_ID('dim')     IS NULL EXEC('CREATE SCHEMA dim');
IF SCHEMA_ID('fact')    IS NULL EXEC('CREATE SCHEMA fact');
GO
PRINT '[01] Schemas etl/staging/dim/fact crees dans OrionETL';
GO

-- Schema dans OrionOLTP
USE OrionOLTP;
GO
IF SCHEMA_ID('ops') IS NULL EXEC('CREATE SCHEMA ops');
GO
PRINT '[01] Schema ops cree dans OrionOLTP';
GO

-- Schema dans OrionDWH
USE OrionDWH;
GO
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw');
GO
PRINT '[01] Schema dw cree dans OrionDWH';
GO

PRINT '[01] OK -- 3 bases creees avec collation French_CI_AS';
GO
