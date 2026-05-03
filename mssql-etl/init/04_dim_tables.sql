-- ============================================================================
--  04 — Tables dimensionnelles côté SQL Server (zone "gold" transitoire).
--  Le DWH PostgreSQL en est le miroir final ; on garde la copie SQL Server
--  pour exécuter les procédures stockées localement.
-- ============================================================================
USE OrionETL;
GO

IF OBJECT_ID(N'dim.dim_date','U') IS NOT NULL DROP TABLE dim.dim_date;
CREATE TABLE dim.dim_date (
    cle_date           INT          NOT NULL PRIMARY KEY,
    date_complete      DATE         NOT NULL UNIQUE,
    jour_du_mois       SMALLINT     NOT NULL,
    numero_mois        SMALLINT     NOT NULL,
    nom_mois           NVARCHAR(12) NOT NULL,
    numero_trimestre   SMALLINT     NOT NULL,
    annee              SMALLINT     NOT NULL,
    jour_de_semaine    SMALLINT     NOT NULL,
    nom_jour           NVARCHAR(12) NOT NULL,
    semaine_annee      SMALLINT     NOT NULL,
    est_weekend        BIT          NOT NULL,
    saison             NVARCHAR(10) NOT NULL
);
GO

IF OBJECT_ID(N'dim.dim_canal','U') IS NOT NULL DROP TABLE dim.dim_canal;
CREATE TABLE dim.dim_canal (
    cle_canal     SMALLINT IDENTITY(1,1) PRIMARY KEY,
    canal_id      SMALLINT NOT NULL UNIQUE,
    code_canal    NVARCHAR(20) NOT NULL,
    nom_canal     NVARCHAR(50) NOT NULL
);
GO

IF OBJECT_ID(N'dim.dim_geographie','U') IS NOT NULL DROP TABLE dim.dim_geographie;
CREATE TABLE dim.dim_geographie (
    cle_geographie  BIGINT IDENTITY(1,1) PRIMARY KEY,
    ville_id        INT NOT NULL UNIQUE,
    nom_ville       NVARCHAR(100) NOT NULL,
    nom_region      NVARCHAR(100) NOT NULL,
    code_pays       CHAR(2)       NOT NULL,
    nom_pays        NVARCHAR(100) NOT NULL,
    nom_continent   NVARCHAR(50)  NOT NULL,
    code_postal     NVARCHAR(20)  NULL
);
GO

IF OBJECT_ID(N'dim.dim_fournisseur','U') IS NOT NULL DROP TABLE dim.dim_fournisseur;
CREATE TABLE dim.dim_fournisseur (
    cle_fournisseur  BIGINT IDENTITY(1,1) PRIMARY KEY,
    fournisseur_id   INT NOT NULL UNIQUE,
    nom_fournisseur  NVARCHAR(120) NOT NULL,
    nom_pays         NVARCHAR(100) NOT NULL,
    nom_continent    NVARCHAR(50)  NOT NULL
);
GO

IF OBJECT_ID(N'dim.dim_produit','U') IS NOT NULL DROP TABLE dim.dim_produit;
CREATE TABLE dim.dim_produit (
    cle_produit             BIGINT IDENTITY(1,1) PRIMARY KEY,
    produit_id              BIGINT NOT NULL UNIQUE,
    nom_produit             NVARCHAR(150) NOT NULL,
    nom_groupe_produit      NVARCHAR(100) NOT NULL,
    nom_categorie_produit   NVARCHAR(100) NOT NULL,
    nom_ligne_produit       NVARCHAR(100) NOT NULL,
    fournisseur_id_naturel  INT NOT NULL,
    nom_fournisseur         NVARCHAR(120) NOT NULL,
    actif                   BIT NOT NULL,
    maj_le                  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'dim.dim_client','U') IS NOT NULL DROP TABLE dim.dim_client;
CREATE TABLE dim.dim_client (
    cle_client          BIGINT IDENTITY(1,1) PRIMARY KEY,
    client_id           BIGINT NOT NULL,
    nom_complet         NVARCHAR(160) NOT NULL,
    sexe                CHAR(1) NULL,
    tranche_age         NVARCHAR(20) NULL,
    groupe_client       NVARCHAR(80) NULL,
    a_carte_fidelite    BIT NOT NULL,
    nom_ville           NVARCHAR(100) NULL,
    nom_pays            NVARCHAR(100) NULL,
    nom_continent       NVARCHAR(50)  NULL,
    -- SCD2
    effectif_du         DATE NOT NULL,
    effectif_au         DATE NULL,
    est_courant         BIT  NOT NULL,
    hash_ligne          CHAR(64) NOT NULL
);
CREATE INDEX idx_dim_client_naturel ON dim.dim_client(client_id, est_courant);
GO

IF OBJECT_ID(N'dim.dim_employe','U') IS NOT NULL DROP TABLE dim.dim_employe;
CREATE TABLE dim.dim_employe (
    cle_employe         BIGINT IDENTITY(1,1) PRIMARY KEY,
    employe_id          BIGINT NOT NULL,
    nom_complet         NVARCHAR(160) NOT NULL,
    sexe                CHAR(1) NOT NULL,
    tranche_age         NVARCHAR(20) NOT NULL,
    salaire             DECIMAL(12,2) NOT NULL,
    tranche_salaire     NVARCHAR(20) NOT NULL,
    org_pays            NVARCHAR(50) NULL,
    org_compagnie       NVARCHAR(100) NULL,
    org_departement     NVARCHAR(100) NULL,
    org_section         NVARCHAR(100) NULL,
    org_groupe          NVARCHAR(100) NULL,
    nom_manager         NVARCHAR(160) NULL,
    date_embauche       DATE NOT NULL,
    date_depart         DATE NULL,
    -- SCD2
    effectif_du         DATE NOT NULL,
    effectif_au         DATE NULL,
    est_courant         BIT NOT NULL,
    hash_ligne          CHAR(64) NOT NULL
);
CREATE INDEX idx_dim_employe_naturel ON dim.dim_employe(employe_id, est_courant);
GO

IF OBJECT_ID(N'fact.fait_ventes','U') IS NOT NULL DROP TABLE fact.fait_ventes;
CREATE TABLE fact.fait_ventes (
    fait_id                 BIGINT IDENTITY(1,1) PRIMARY KEY,
    cle_date                INT      NOT NULL,
    cle_produit             BIGINT   NOT NULL,
    cle_client              BIGINT   NOT NULL,
    cle_employe             BIGINT   NOT NULL,
    cle_fournisseur         BIGINT   NOT NULL,
    cle_canal               SMALLINT NOT NULL,
    cle_geographie_client   BIGINT   NOT NULL,
    commande_id             BIGINT   NOT NULL,
    numero_ligne            SMALLINT NOT NULL,
    quantite                DECIMAL(12,3) NOT NULL,
    prix_unitaire           DECIMAL(12,2) NOT NULL,
    cout_unitaire           DECIMAL(12,2) NOT NULL,
    pct_remise              DECIMAL(5,4)  NOT NULL,
    montant_brut            DECIMAL(14,2) NOT NULL,
    montant_remise          DECIMAL(14,2) NOT NULL,
    montant_net             DECIMAL(14,2) NOT NULL,
    montant_cout            DECIMAL(14,2) NOT NULL,
    montant_marge           DECIMAL(14,2) NOT NULL,
    UNIQUE (commande_id, numero_ligne)
);
GO

PRINT '[04] Tables dim.* + fact.fait_ventes (FR) créées.';
GO
