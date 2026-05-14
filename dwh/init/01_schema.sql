-- ================================================================
--  Orion DWH — Schéma en étoile (nomenclature française)
-- ================================================================
CREATE SCHEMA IF NOT EXISTS dw;
SET search_path TO dw, public;

-- ----------------------------------------------------------------
-- Méta : watermarks et journal d'exécution
-- (technique, conservé en anglais pour l'outillage)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS etl_watermark (
    job_name    VARCHAR(80) PRIMARY KEY,
    last_value  TIMESTAMP NOT NULL,
    updated_at  TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etl_run_log (
    run_id     BIGSERIAL PRIMARY KEY,
    job_name   VARCHAR(80) NOT NULL,
    started_at TIMESTAMP NOT NULL DEFAULT now(),
    ended_at   TIMESTAMP,
    status     VARCHAR(16) NOT NULL DEFAULT 'RUNNING',
    rows_in    BIGINT,
    rows_out   BIGINT,
    error_msg  TEXT
);

-- ----------------------------------------------------------------
-- Dimension Date (statique, peuplée une fois)
-- ----------------------------------------------------------------
CREATE TABLE dim_date (
    cle_date          INT          PRIMARY KEY,         -- AAAAMMJJ
    date_complete     DATE         NOT NULL UNIQUE,
    jour_du_mois      SMALLINT     NOT NULL,
    numero_mois       SMALLINT     NOT NULL,
    nom_mois          VARCHAR(12)  NOT NULL,
    numero_trimestre  SMALLINT     NOT NULL,
    annee             SMALLINT     NOT NULL,
    jour_de_semaine   SMALLINT     NOT NULL,            -- 1 = lundi
    nom_jour          VARCHAR(12)  NOT NULL,
    semaine_annee     SMALLINT     NOT NULL,
    est_weekend       BOOLEAN      NOT NULL,
    saison            VARCHAR(10)  NOT NULL
);

-- ----------------------------------------------------------------
-- Dimensions SCD1
-- ----------------------------------------------------------------
CREATE TABLE dim_canal (
    cle_canal     SMALLSERIAL PRIMARY KEY,
    canal_id      SMALLINT NOT NULL UNIQUE,             -- clé naturelle OLTP
    code_canal    VARCHAR(20) NOT NULL,
    nom_canal     VARCHAR(50) NOT NULL
);

CREATE TABLE dim_geographie (
    cle_geographie  BIGSERIAL PRIMARY KEY,
    ville_id        INT NOT NULL UNIQUE,                -- clé naturelle (ville OLTP)
    nom_ville       VARCHAR(100) NOT NULL,
    nom_region      VARCHAR(100) NOT NULL,
    code_pays       CHAR(2)      NOT NULL,
    nom_pays        VARCHAR(100) NOT NULL,
    nom_continent   VARCHAR(50)  NOT NULL,
    code_postal     VARCHAR(20)
);

CREATE TABLE dim_fournisseur (
    cle_fournisseur  BIGSERIAL PRIMARY KEY,
    fournisseur_id   INT NOT NULL UNIQUE,               -- clé naturelle
    nom_fournisseur  VARCHAR(120) NOT NULL,
    nom_pays         VARCHAR(100) NOT NULL,
    nom_continent    VARCHAR(50)  NOT NULL
);

CREATE TABLE dim_produit (
    cle_produit             BIGSERIAL PRIMARY KEY,
    produit_id              BIGINT       NOT NULL UNIQUE,
    nom_produit             VARCHAR(150) NOT NULL,
    nom_groupe_produit      VARCHAR(100) NOT NULL,
    nom_categorie_produit   VARCHAR(100) NOT NULL,
    nom_ligne_produit       VARCHAR(100) NOT NULL,
    fournisseur_id_naturel  INT          NOT NULL,
    nom_fournisseur         VARCHAR(120) NOT NULL,
    actif                   BOOLEAN      NOT NULL,
    maj_le                  TIMESTAMP    NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------
-- Dimensions SCD2
-- ----------------------------------------------------------------
CREATE TABLE dim_client (
    cle_client          BIGSERIAL    PRIMARY KEY,
    client_id           BIGINT       NOT NULL,
    nom_complet         VARCHAR(160) NOT NULL,
    sexe                CHAR(1),
    tranche_age         VARCHAR(20),                    -- '<25','25-34',...
    groupe_client       VARCHAR(80),
    a_carte_fidelite    BOOLEAN      NOT NULL,
    nom_ville           VARCHAR(100),
    nom_pays            VARCHAR(100),
    nom_continent       VARCHAR(50),
    -- SCD2
    effectif_du         DATE         NOT NULL,
    effectif_au         DATE,
    est_courant         BOOLEAN      NOT NULL,
    hash_ligne          CHAR(64)     NOT NULL
);
CREATE INDEX idx_dim_client_naturel ON dim_client(client_id, est_courant);
CREATE INDEX idx_dim_client_periode ON dim_client(client_id, effectif_du, effectif_au);

CREATE TABLE dim_employe (
    cle_employe         BIGSERIAL     PRIMARY KEY,
    employe_id          BIGINT        NOT NULL,
    nom_complet         VARCHAR(160)  NOT NULL,
    sexe                CHAR(1)       NOT NULL,
    tranche_age         VARCHAR(20)   NOT NULL,
    salaire             NUMERIC(12,2) NOT NULL,
    tranche_salaire     VARCHAR(20)   NOT NULL,
    org_pays            VARCHAR(50),
    org_compagnie       VARCHAR(100),
    org_departement     VARCHAR(100),
    org_section         VARCHAR(100),
    org_groupe          VARCHAR(100),
    nom_manager         VARCHAR(160),
    date_embauche       DATE          NOT NULL,
    date_depart         DATE,
    -- Reflet du contrat (cf. doc/rapport/modelisation-revue.pdf §4.6)
    type_contrat_courant VARCHAR(30),
    date_debut_contrat   DATE,
    date_fin_contrat     DATE,
    statut_contrat       VARCHAR(20),
    nb_contrats_signes   INT,
    -- SCD2
    effectif_du         DATE          NOT NULL,
    effectif_au         DATE,
    est_courant         BOOLEAN       NOT NULL,
    hash_ligne          CHAR(64)      NOT NULL
);
CREATE INDEX idx_dim_employe_naturel ON dim_employe(employe_id, est_courant);
CREATE INDEX idx_dim_employe_periode ON dim_employe(employe_id, effectif_du, effectif_au);

-- ----------------------------------------------------------------
-- Table de faits : ligne de commande
-- ----------------------------------------------------------------
CREATE TABLE fait_ventes (
    fait_id                  BIGSERIAL PRIMARY KEY,
    cle_date                 INT      NOT NULL REFERENCES dim_date(cle_date),
    cle_produit              BIGINT   NOT NULL REFERENCES dim_produit(cle_produit),
    cle_client               BIGINT   NOT NULL REFERENCES dim_client(cle_client),
    cle_employe              BIGINT   NOT NULL REFERENCES dim_employe(cle_employe),
    cle_fournisseur          BIGINT   NOT NULL REFERENCES dim_fournisseur(cle_fournisseur),
    cle_canal                SMALLINT NOT NULL REFERENCES dim_canal(cle_canal),
    cle_geographie_client    BIGINT   NOT NULL REFERENCES dim_geographie(cle_geographie),
    -- Degenerate dimensions
    commande_id              BIGINT   NOT NULL,
    numero_ligne             SMALLINT NOT NULL,
    -- Mesures
    quantite                 NUMERIC(12,3) NOT NULL,
    prix_unitaire            NUMERIC(12,2) NOT NULL,
    cout_unitaire            NUMERIC(12,2) NOT NULL,
    pct_remise               NUMERIC(5,4)  NOT NULL,
    montant_brut             NUMERIC(14,2) NOT NULL,
    montant_remise           NUMERIC(14,2) NOT NULL,
    montant_net              NUMERIC(14,2) NOT NULL,    -- chiffre d'affaires
    montant_cout             NUMERIC(14,2) NOT NULL,
    montant_marge            NUMERIC(14,2) NOT NULL,
    UNIQUE (commande_id, numero_ligne)
);
CREATE INDEX idx_fait_date        ON fait_ventes(cle_date);
CREATE INDEX idx_fait_produit     ON fait_ventes(cle_produit);
CREATE INDEX idx_fait_client      ON fait_ventes(cle_client);
CREATE INDEX idx_fait_employe     ON fait_ventes(cle_employe);
CREATE INDEX idx_fait_fournisseur ON fait_ventes(cle_fournisseur);
CREATE INDEX idx_fait_canal       ON fait_ventes(cle_canal);

COMMENT ON SCHEMA dw IS 'Orion DWH — schéma en étoile (nomenclature française)';
