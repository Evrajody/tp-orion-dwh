-- ============================================================================
--  03 — Tables de staging (miroir simplifié de l'OLTP Orion).
--  L'orchestrateur copie tel quel les lignes Postgres → ces tables.
--  Aucun calcul n'a lieu ici : c'est la zone d'atterrissage.
-- ============================================================================
USE OrionETL;
GO

-- Géographie (jointe en une seule table dénormalisée)
IF OBJECT_ID(N'staging.geographie_full','U') IS NOT NULL DROP TABLE staging.geographie_full;
CREATE TABLE staging.geographie_full (
    ville_id        INT          NOT NULL PRIMARY KEY,
    nom_ville       NVARCHAR(100) NOT NULL,
    code_postal     NVARCHAR(20)  NULL,
    nom_region      NVARCHAR(100) NOT NULL,
    code_pays       CHAR(2)       NOT NULL,
    nom_pays        NVARCHAR(100) NOT NULL,
    nom_continent   NVARCHAR(50)  NOT NULL
);
GO

IF OBJECT_ID(N'staging.fournisseur_full','U') IS NOT NULL DROP TABLE staging.fournisseur_full;
CREATE TABLE staging.fournisseur_full (
    fournisseur_id   INT NOT NULL PRIMARY KEY,
    nom_fournisseur  NVARCHAR(120) NOT NULL,
    nom_pays         NVARCHAR(100) NOT NULL,
    nom_continent    NVARCHAR(50)  NOT NULL
);
GO

IF OBJECT_ID(N'staging.canal','U') IS NOT NULL DROP TABLE staging.canal;
CREATE TABLE staging.canal (
    canal_id     SMALLINT NOT NULL PRIMARY KEY,
    code_canal   NVARCHAR(20) NOT NULL,
    nom_canal    NVARCHAR(50) NOT NULL
);
GO

IF OBJECT_ID(N'staging.produit_full','U') IS NOT NULL DROP TABLE staging.produit_full;
CREATE TABLE staging.produit_full (
    produit_id              BIGINT NOT NULL PRIMARY KEY,
    nom_produit             NVARCHAR(150) NOT NULL,
    nom_groupe_produit      NVARCHAR(100) NOT NULL,
    nom_categorie_produit   NVARCHAR(100) NOT NULL,
    nom_ligne_produit       NVARCHAR(100) NOT NULL,
    fournisseur_id_naturel  INT NOT NULL,
    nom_fournisseur         NVARCHAR(120) NOT NULL,
    actif                   BIT NOT NULL
);
GO

IF OBJECT_ID(N'staging.client_full','U') IS NOT NULL DROP TABLE staging.client_full;
CREATE TABLE staging.client_full (
    client_id          BIGINT NOT NULL PRIMARY KEY,
    nom_complet        NVARCHAR(160) NOT NULL,
    sexe               CHAR(1) NULL,
    date_naissance     DATE    NULL,
    groupe_client      NVARCHAR(80) NULL,
    a_carte_fidelite   BIT NOT NULL,
    nom_ville          NVARCHAR(100) NULL,
    nom_pays           NVARCHAR(100) NULL,
    nom_continent      NVARCHAR(50)  NULL,
    maj_le             DATETIME2(3) NOT NULL
);
GO

IF OBJECT_ID(N'staging.employe_full','U') IS NOT NULL DROP TABLE staging.employe_full;
CREATE TABLE staging.employe_full (
    employe_id        BIGINT NOT NULL PRIMARY KEY,
    nom_complet       NVARCHAR(160) NOT NULL,
    sexe              CHAR(1) NOT NULL,
    date_naissance    DATE NOT NULL,
    salaire           DECIMAL(12,2) NOT NULL,
    org_pays          NVARCHAR(50) NULL,
    org_compagnie     NVARCHAR(100) NULL,
    org_departement   NVARCHAR(100) NULL,
    org_section       NVARCHAR(100) NULL,
    org_groupe        NVARCHAR(100) NULL,
    nom_manager       NVARCHAR(160) NULL,
    date_embauche     DATE NOT NULL,
    date_depart       DATE NULL,
    maj_le            DATETIME2(3) NOT NULL
);
GO

-- Lignes de commande incrémentales (source de fait_ventes)
IF OBJECT_ID(N'staging.lignes_commande','U') IS NOT NULL DROP TABLE staging.lignes_commande;
CREATE TABLE staging.lignes_commande (
    commande_id     BIGINT NOT NULL,
    numero_ligne    SMALLINT NOT NULL,
    date_commande   DATE NOT NULL,
    client_id       BIGINT NOT NULL,
    employe_id      BIGINT NOT NULL,
    canal_id        SMALLINT NOT NULL,
    produit_id      BIGINT NOT NULL,
    fournisseur_id  INT NOT NULL,
    cli_ville_id    INT NOT NULL,
    quantite        DECIMAL(12,3) NOT NULL,
    prix_unitaire   DECIMAL(12,2) NOT NULL,
    cout_unitaire   DECIMAL(12,2) NOT NULL,
    pct_remise      DECIMAL(5,4)  NOT NULL,
    PRIMARY KEY (commande_id, numero_ligne)
);
GO

PRINT '[03] Tables de staging (FR) créées.';
GO
