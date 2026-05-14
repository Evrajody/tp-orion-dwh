-- ============================================================================
-- 02 -- Schema OLTP 3NF (converti de Postgres vers T-SQL).
-- A executer dans : OrionOLTP
-- Pre-requis      : script 01 execute.
-- Verification    : SELECT COUNT(*) FROM sys.tables WHERE schema_id = SCHEMA_ID('ops');
--                   -> doit retourner 21.
-- ============================================================================
USE OrionOLTP;
GO

-- ----------------------------------------------------------------------------
-- Geographie
-- ----------------------------------------------------------------------------
CREATE TABLE ops.continent (
    continent_id   SMALLINT IDENTITY(1,1) PRIMARY KEY,
    nom_continent  NVARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE ops.pays (
    pays_id        INT IDENTITY(1,1) PRIMARY KEY,
    code_pays      CHAR(2)       NOT NULL UNIQUE,
    nom_pays       NVARCHAR(100) NOT NULL,
    continent_id   SMALLINT      NOT NULL REFERENCES ops.continent(continent_id)
);

CREATE TABLE ops.region (
    region_id      INT IDENTITY(1,1) PRIMARY KEY,
    nom_region     NVARCHAR(100) NOT NULL,
    pays_id        INT           NOT NULL REFERENCES ops.pays(pays_id),
    CONSTRAINT uq_region_pays UNIQUE (nom_region, pays_id)
);

CREATE TABLE ops.ville (
    ville_id       INT IDENTITY(1,1) PRIMARY KEY,
    nom_ville      NVARCHAR(100) NOT NULL,
    code_postal    NVARCHAR(20)  NULL,
    region_id      INT           NOT NULL REFERENCES ops.region(region_id)
);
CREATE INDEX idx_ville_region ON ops.ville(region_id);
GO

-- ----------------------------------------------------------------------------
-- Hierarchie organisationnelle 5 niveaux
-- ----------------------------------------------------------------------------
CREATE TABLE ops.org_pays (
    org_pays_id    SMALLINT IDENTITY(1,1) PRIMARY KEY,
    nom_org_pays   NVARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE ops.org_compagnie (
    org_compagnie_id   INT IDENTITY(1,1) PRIMARY KEY,
    nom_org_compagnie  NVARCHAR(100) NOT NULL,
    org_pays_id        SMALLINT      NOT NULL REFERENCES ops.org_pays(org_pays_id),
    CONSTRAINT uq_compagnie_pays UNIQUE (nom_org_compagnie, org_pays_id)
);

CREATE TABLE ops.org_departement (
    org_departement_id   INT IDENTITY(1,1) PRIMARY KEY,
    nom_org_departement  NVARCHAR(100) NOT NULL,
    org_compagnie_id     INT           NOT NULL REFERENCES ops.org_compagnie(org_compagnie_id),
    CONSTRAINT uq_dept_compagnie UNIQUE (nom_org_departement, org_compagnie_id)
);

CREATE TABLE ops.org_section (
    org_section_id      INT IDENTITY(1,1) PRIMARY KEY,
    nom_org_section     NVARCHAR(100) NOT NULL,
    org_departement_id  INT           NOT NULL REFERENCES ops.org_departement(org_departement_id),
    CONSTRAINT uq_section_dept UNIQUE (nom_org_section, org_departement_id)
);

CREATE TABLE ops.org_groupe (
    org_groupe_id    INT IDENTITY(1,1) PRIMARY KEY,
    nom_org_groupe   NVARCHAR(100) NOT NULL,
    org_section_id   INT           NOT NULL REFERENCES ops.org_section(org_section_id),
    CONSTRAINT uq_groupe_section UNIQUE (nom_org_groupe, org_section_id)
);
GO

-- ----------------------------------------------------------------------------
-- Employes + contrats
-- ----------------------------------------------------------------------------
CREATE TABLE ops.employe (
    employe_id     BIGINT IDENTITY(1,1) PRIMARY KEY,
    nom            NVARCHAR(80)   NOT NULL,
    prenom         NVARCHAR(80)   NOT NULL,
    sexe           CHAR(1)        NOT NULL CHECK (sexe IN ('M','F')),
    date_naissance DATE           NOT NULL,
    date_embauche  DATE           NOT NULL,
    date_depart    DATE           NULL,
    salaire        DECIMAL(12,2)  NOT NULL CHECK (salaire >= 0),
    manager_id     BIGINT         NULL REFERENCES ops.employe(employe_id),
    org_groupe_id  INT            NOT NULL REFERENCES ops.org_groupe(org_groupe_id),
    rue            NVARCHAR(200)  NULL,
    ville_id       INT            NULL REFERENCES ops.ville(ville_id),
    maj_le         DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE INDEX idx_employe_org_groupe ON ops.employe(org_groupe_id);
CREATE INDEX idx_employe_manager    ON ops.employe(manager_id);

CREATE TABLE ops.contrat_employe (
    contrat_id    BIGINT IDENTITY(1,1) PRIMARY KEY,
    employe_id    BIGINT       NOT NULL REFERENCES ops.employe(employe_id) ON DELETE CASCADE,
    date_debut    DATE         NOT NULL,
    date_fin      DATE         NULL,
    type_contrat  NVARCHAR(30) NOT NULL
                    CHECK (type_contrat IN ('CDI','CDD','Interim','Stage','Alternance','Freelance')),
    CONSTRAINT ck_contrat_dates CHECK (date_fin IS NULL OR date_fin >= date_debut)
);
CREATE INDEX idx_contrat_employe ON ops.contrat_employe(employe_id, date_debut DESC);
GO

-- ----------------------------------------------------------------------------
-- Hierarchie produit + fournisseurs + historique prix + remises
-- ----------------------------------------------------------------------------
CREATE TABLE ops.fournisseur (
    fournisseur_id    INT IDENTITY(1,1) PRIMARY KEY,
    nom_fournisseur   NVARCHAR(120) NOT NULL,
    pays_id           INT           NOT NULL REFERENCES ops.pays(pays_id)
);

CREATE TABLE ops.ligne_produit (
    ligne_produit_id   INT IDENTITY(1,1) PRIMARY KEY,
    nom_ligne_produit  NVARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE ops.categorie_produit (
    categorie_produit_id   INT IDENTITY(1,1) PRIMARY KEY,
    nom_categorie_produit  NVARCHAR(100) NOT NULL,
    ligne_produit_id       INT           NOT NULL REFERENCES ops.ligne_produit(ligne_produit_id),
    CONSTRAINT uq_categorie_ligne UNIQUE (nom_categorie_produit, ligne_produit_id)
);

CREATE TABLE ops.groupe_produit (
    groupe_produit_id      INT IDENTITY(1,1) PRIMARY KEY,
    nom_groupe_produit     NVARCHAR(100) NOT NULL,
    categorie_produit_id   INT           NOT NULL REFERENCES ops.categorie_produit(categorie_produit_id),
    CONSTRAINT uq_groupe_categorie UNIQUE (nom_groupe_produit, categorie_produit_id)
);

CREATE TABLE ops.produit (
    produit_id         BIGINT IDENTITY(1,1) PRIMARY KEY,
    nom_produit        NVARCHAR(150) NOT NULL,
    groupe_produit_id  INT     NOT NULL REFERENCES ops.groupe_produit(groupe_produit_id),
    fournisseur_id     INT     NOT NULL REFERENCES ops.fournisseur(fournisseur_id),
    actif              BIT     NOT NULL DEFAULT 1,
    cree_le            DATE    NOT NULL DEFAULT (CAST(SYSUTCDATETIME() AS DATE))
);
CREATE INDEX idx_produit_groupe      ON ops.produit(groupe_produit_id);
CREATE INDEX idx_produit_fournisseur ON ops.produit(fournisseur_id);

CREATE TABLE ops.historique_prix (
    prix_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    produit_id   BIGINT        NOT NULL REFERENCES ops.produit(produit_id) ON DELETE CASCADE,
    date_debut   DATE          NOT NULL,
    date_fin     DATE          NULL,
    cout         DECIMAL(12,2) NOT NULL CHECK (cout >= 0),
    prix_vente   DECIMAL(12,2) NOT NULL CHECK (prix_vente >= 0),
    CONSTRAINT ck_prix_dates CHECK (date_fin IS NULL OR date_fin >= date_debut)
);
CREATE INDEX idx_historique_prix_periode ON ops.historique_prix(produit_id, date_debut, date_fin);

CREATE TABLE ops.remise_produit (
    remise_id    BIGINT IDENTITY(1,1) PRIMARY KEY,
    produit_id   BIGINT        NOT NULL REFERENCES ops.produit(produit_id) ON DELETE CASCADE,
    date_debut   DATE          NOT NULL,
    date_fin     DATE          NOT NULL,
    pct_remise   DECIMAL(5,4)  NOT NULL CHECK (pct_remise BETWEEN 0 AND 1),
    CONSTRAINT ck_remise_dates CHECK (date_fin >= date_debut)
);
CREATE INDEX idx_remise_periode ON ops.remise_produit(produit_id, date_debut, date_fin);
GO

-- ----------------------------------------------------------------------------
-- Clients + groupes + carte fidelite
-- ----------------------------------------------------------------------------
CREATE TABLE ops.groupe_client (
    groupe_client_id   INT IDENTITY(1,1) PRIMARY KEY,
    nom_groupe_client  NVARCHAR(80)  NOT NULL UNIQUE,
    description        NVARCHAR(255) NULL
);

CREATE TABLE ops.client (
    client_id          BIGINT IDENTITY(1,1) PRIMARY KEY,
    nom                NVARCHAR(80) NOT NULL,
    prenom             NVARCHAR(80) NOT NULL,
    sexe               CHAR(1)      NULL CHECK (sexe IN ('M','F')),
    date_naissance     DATE         NULL,
    groupe_client_id   INT          NULL REFERENCES ops.groupe_client(groupe_client_id),
    rue                NVARCHAR(200) NULL,
    ville_id           INT          NOT NULL REFERENCES ops.ville(ville_id),
    actif              BIT          NOT NULL DEFAULT 1,
    cree_le            DATE         NOT NULL DEFAULT (CAST(SYSUTCDATETIME() AS DATE)),
    maj_le             DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE INDEX idx_client_ville  ON ops.client(ville_id);
CREATE INDEX idx_client_groupe ON ops.client(groupe_client_id);

CREATE TABLE ops.carte_fidelite (
    carte_fidelite_id  BIGINT IDENTITY(1,1) PRIMARY KEY,
    client_id          BIGINT       NOT NULL UNIQUE REFERENCES ops.client(client_id) ON DELETE CASCADE,
    numero_carte       NVARCHAR(20) NOT NULL UNIQUE,
    date_emission      DATE         NOT NULL,
    nom_programme      NVARCHAR(50) NOT NULL DEFAULT 'Orion Star Club'
);
GO

-- ----------------------------------------------------------------------------
-- Canaux de vente + commandes
-- ----------------------------------------------------------------------------
CREATE TABLE ops.canal_vente (
    canal_id     SMALLINT IDENTITY(1,1) PRIMARY KEY,
    code_canal   NVARCHAR(20) NOT NULL UNIQUE,
    nom_canal    NVARCHAR(50) NOT NULL
);

CREATE TABLE ops.commande (
    commande_id    BIGINT IDENTITY(1,1) PRIMARY KEY,
    date_commande  DATE          NOT NULL,
    client_id      BIGINT        NOT NULL REFERENCES ops.client(client_id),
    employe_id     BIGINT        NOT NULL REFERENCES ops.employe(employe_id),
    canal_id       SMALLINT      NOT NULL REFERENCES ops.canal_vente(canal_id),
    montant_total  DECIMAL(14,2) NOT NULL DEFAULT 0,
    cree_le        DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE INDEX idx_commande_date    ON ops.commande(date_commande);
CREATE INDEX idx_commande_client  ON ops.commande(client_id);
CREATE INDEX idx_commande_employe ON ops.commande(employe_id);

CREATE TABLE ops.ligne_commande (
    commande_id     BIGINT        NOT NULL REFERENCES ops.commande(commande_id) ON DELETE CASCADE,
    numero_ligne    SMALLINT      NOT NULL,
    produit_id      BIGINT        NOT NULL REFERENCES ops.produit(produit_id),
    quantite        DECIMAL(12,3) NOT NULL CHECK (quantite > 0),
    prix_unitaire   DECIMAL(12,2) NOT NULL CHECK (prix_unitaire >= 0),
    cout_unitaire   DECIMAL(12,2) NOT NULL CHECK (cout_unitaire >= 0),
    pct_remise      DECIMAL(5,4)  NOT NULL DEFAULT 0
                    CHECK (pct_remise BETWEEN 0 AND 1),
    CONSTRAINT pk_ligne_commande PRIMARY KEY (commande_id, numero_ligne)
);
CREATE INDEX idx_ligne_commande_produit ON ops.ligne_commande(produit_id);
GO

PRINT '[02] OK -- schema ops cree (21 tables)';
GO
