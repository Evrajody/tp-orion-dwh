-- ============================================================================
-- 10 -- Schema DWH (modele en etoile) -- converti de Postgres vers T-SQL.
-- A executer dans : OrionDWH
-- Pre-requis      : script 01 execute (la base OrionDWH et son schema dw doivent exister).
-- Verification    : SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID('dw');
--                   -> doit retourner 10.
-- ============================================================================
USE OrionDWH;
GO

-- ----------------------------------------------------------------------------
-- Meta : watermarks et journal d'execution (techniques)
-- ----------------------------------------------------------------------------
IF OBJECT_ID('dw.etl_watermark','U') IS NULL
CREATE TABLE dw.etl_watermark (
    job_name    NVARCHAR(80) PRIMARY KEY,
    last_value  DATETIME2(3) NOT NULL,
    updated_at  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);

IF OBJECT_ID('dw.etl_run_log','U') IS NULL
CREATE TABLE dw.etl_run_log (
    run_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    job_name   NVARCHAR(80)  NOT NULL,
    started_at DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    ended_at   DATETIME2(3)  NULL,
    status     NVARCHAR(16)  NOT NULL DEFAULT 'RUNNING',
    rows_in    BIGINT        NULL,
    rows_out   BIGINT        NULL,
    error_msg  NVARCHAR(MAX) NULL
);
GO

-- ----------------------------------------------------------------------------
-- Dimension Date (statique, peuplee une fois)
-- ----------------------------------------------------------------------------
CREATE TABLE dw.dim_date (
    cle_date          INT          PRIMARY KEY,
    date_complete     DATE         NOT NULL UNIQUE,
    jour_du_mois      SMALLINT     NOT NULL,
    numero_mois       SMALLINT     NOT NULL,
    nom_mois          NVARCHAR(12) NOT NULL,
    numero_trimestre  SMALLINT     NOT NULL,
    annee             SMALLINT     NOT NULL,
    jour_de_semaine   SMALLINT     NOT NULL,
    nom_jour          NVARCHAR(12) NOT NULL,
    semaine_annee     SMALLINT     NOT NULL,
    est_weekend       BIT          NOT NULL,
    saison            NVARCHAR(10) NOT NULL
);
GO

-- ----------------------------------------------------------------------------
-- Dimensions SCD1
-- ----------------------------------------------------------------------------
CREATE TABLE dw.dim_canal (
    cle_canal     SMALLINT IDENTITY(1,1) PRIMARY KEY,
    canal_id      SMALLINT     NOT NULL UNIQUE,
    code_canal    NVARCHAR(20) NOT NULL,
    nom_canal     NVARCHAR(50) NOT NULL
);

CREATE TABLE dw.dim_geographie (
    cle_geographie  BIGINT IDENTITY(1,1) PRIMARY KEY,
    ville_id        INT           NOT NULL UNIQUE,
    nom_ville       NVARCHAR(100) NOT NULL,
    nom_region      NVARCHAR(100) NOT NULL,
    code_pays       NCHAR(2)       NOT NULL,
    nom_pays        NVARCHAR(100) NOT NULL,
    nom_continent   NVARCHAR(50)  NOT NULL,
    code_postal     NVARCHAR(20)  NULL
);

CREATE TABLE dw.dim_fournisseur (
    cle_fournisseur  BIGINT IDENTITY(1,1) PRIMARY KEY,
    fournisseur_id   INT           NOT NULL UNIQUE,
    nom_fournisseur  NVARCHAR(120) NOT NULL,
    nom_pays         NVARCHAR(100) NOT NULL,
    nom_continent    NVARCHAR(50)  NOT NULL
);

CREATE TABLE dw.dim_produit (
    cle_produit             BIGINT IDENTITY(1,1) PRIMARY KEY,
    produit_id              BIGINT        NOT NULL UNIQUE,
    nom_produit             NVARCHAR(150) NOT NULL,
    nom_groupe_produit      NVARCHAR(100) NOT NULL,
    nom_categorie_produit   NVARCHAR(100) NOT NULL,
    nom_ligne_produit       NVARCHAR(100) NOT NULL,
    fournisseur_id_naturel  INT           NOT NULL,
    nom_fournisseur         NVARCHAR(120) NOT NULL,
    actif                   BIT           NOT NULL,
    maj_le                  DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- ----------------------------------------------------------------------------
-- Dimensions SCD2 (avec colonnes contrat sur dim_employe)
-- ----------------------------------------------------------------------------
CREATE TABLE dw.dim_client (
    cle_client          BIGINT IDENTITY(1,1) PRIMARY KEY,
    client_id           BIGINT        NOT NULL,
    nom_complet         NVARCHAR(160) NOT NULL,
    sexe                NCHAR(1)       NULL,
    tranche_age         NVARCHAR(20)  NULL,
    groupe_client       NVARCHAR(80)  NULL,
    a_carte_fidelite    BIT           NOT NULL,
    nom_ville           NVARCHAR(100) NULL,
    nom_pays            NVARCHAR(100) NULL,
    nom_continent       NVARCHAR(50)  NULL,
    -- SCD2
    effectif_du         DATE          NOT NULL,
    effectif_au         DATE          NULL,
    est_courant         BIT           NOT NULL,
    hash_ligne          NCHAR(64)      NOT NULL
);
CREATE INDEX idx_dim_client_naturel ON dw.dim_client(client_id, est_courant);
CREATE INDEX idx_dim_client_periode ON dw.dim_client(client_id, effectif_du, effectif_au);

CREATE TABLE dw.dim_employe (
    cle_employe          BIGINT IDENTITY(1,1) PRIMARY KEY,
    employe_id           BIGINT        NOT NULL,
    nom_complet          NVARCHAR(160) NOT NULL,
    sexe                 NCHAR(1)       NOT NULL,
    tranche_age          NVARCHAR(20)  NOT NULL,
    salaire              DECIMAL(12,2) NOT NULL,
    tranche_salaire      NVARCHAR(20)  NOT NULL,
    org_pays             NVARCHAR(50)  NULL,
    org_compagnie        NVARCHAR(100) NULL,
    org_departement      NVARCHAR(100) NULL,
    org_section          NVARCHAR(100) NULL,
    org_groupe           NVARCHAR(100) NULL,
    nom_manager          NVARCHAR(160) NULL,
    date_embauche        DATE          NOT NULL,
    date_depart          DATE          NULL,
    -- Reflet du contrat (cf. modelisation-revue.pdf section 4)
    type_contrat_courant NVARCHAR(30)  NULL,
    date_debut_contrat   DATE          NULL,
    date_fin_contrat     DATE          NULL,
    statut_contrat       NVARCHAR(20)  NULL,
    nb_contrats_signes   INT           NULL,
    -- SCD2
    effectif_du          DATE          NOT NULL,
    effectif_au          DATE          NULL,
    est_courant          BIT           NOT NULL,
    hash_ligne           NCHAR(64)      NOT NULL
);
CREATE INDEX idx_dim_employe_naturel ON dw.dim_employe(employe_id, est_courant);
CREATE INDEX idx_dim_employe_periode ON dw.dim_employe(employe_id, effectif_du, effectif_au);
GO

-- ----------------------------------------------------------------------------
-- Table de faits : grain ligne de commande
-- ----------------------------------------------------------------------------
CREATE TABLE dw.fait_ventes (
    fait_id                  BIGINT IDENTITY(1,1) PRIMARY KEY,
    cle_date                 INT      NOT NULL REFERENCES dw.dim_date(cle_date),
    cle_produit              BIGINT   NOT NULL REFERENCES dw.dim_produit(cle_produit),
    cle_client               BIGINT   NOT NULL REFERENCES dw.dim_client(cle_client),
    cle_employe              BIGINT   NOT NULL REFERENCES dw.dim_employe(cle_employe),
    cle_fournisseur          BIGINT   NOT NULL REFERENCES dw.dim_fournisseur(cle_fournisseur),
    cle_canal                SMALLINT NOT NULL REFERENCES dw.dim_canal(cle_canal),
    cle_geographie_client    BIGINT   NOT NULL REFERENCES dw.dim_geographie(cle_geographie),
    -- Degenerate dimensions
    commande_id              BIGINT   NOT NULL,
    numero_ligne             SMALLINT NOT NULL,
    -- Mesures
    quantite                 DECIMAL(12,3) NOT NULL,
    prix_unitaire            DECIMAL(12,2) NOT NULL,
    cout_unitaire            DECIMAL(12,2) NOT NULL,
    pct_remise               DECIMAL(5,4)  NOT NULL,
    montant_brut             DECIMAL(14,2) NOT NULL,
    montant_remise           DECIMAL(14,2) NOT NULL,
    montant_net              DECIMAL(14,2) NOT NULL,    -- chiffre d'affaires
    montant_cout             DECIMAL(14,2) NOT NULL,
    montant_marge            DECIMAL(14,2) NOT NULL,
    CONSTRAINT uq_fait_commande_ligne UNIQUE (commande_id, numero_ligne)
);
CREATE INDEX idx_fait_date        ON dw.fait_ventes(cle_date);
CREATE INDEX idx_fait_produit     ON dw.fait_ventes(cle_produit);
CREATE INDEX idx_fait_client      ON dw.fait_ventes(cle_client);
CREATE INDEX idx_fait_employe     ON dw.fait_ventes(cle_employe);
CREATE INDEX idx_fait_fournisseur ON dw.fait_ventes(cle_fournisseur);
CREATE INDEX idx_fait_canal       ON dw.fait_ventes(cle_canal);
GO

PRINT '[10] OK -- schema dw cree (10 tables : 7 dim + fact + 2 meta)';
GO
