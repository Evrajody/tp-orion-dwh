-- ================================================================
--  Orion — Base opérationnelle (OLTP) — modèle 3NF
--  Toutes les tables sont rangées dans le schéma "ops".
--
--  Conventions :
--   * nomenclature française (cf. doc/MODELISATION.md)
--   * clés primaires techniques nommées <table>_id
--   * pas de NULL sur les FK obligatoires
--   * tous les montants en USD (cf. énoncé)
-- ================================================================

CREATE SCHEMA IF NOT EXISTS ops;
SET search_path TO ops, public;

-- ----------------------------------------------------------------
-- Géographie (utilisée par fournisseurs et clients)
-- ----------------------------------------------------------------
CREATE TABLE continent (
    continent_id   SMALLSERIAL PRIMARY KEY,
    nom_continent  VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE pays (
    pays_id        SERIAL PRIMARY KEY,
    code_pays      CHAR(2)      NOT NULL UNIQUE,
    nom_pays       VARCHAR(100) NOT NULL,
    continent_id   SMALLINT     NOT NULL REFERENCES continent(continent_id)
);

CREATE TABLE region (
    region_id      SERIAL PRIMARY KEY,
    nom_region     VARCHAR(100) NOT NULL,
    pays_id        INT          NOT NULL REFERENCES pays(pays_id),
    UNIQUE (nom_region, pays_id)
);

CREATE TABLE ville (
    ville_id       SERIAL PRIMARY KEY,
    nom_ville      VARCHAR(100) NOT NULL,
    code_postal    VARCHAR(20),
    region_id      INT          NOT NULL REFERENCES region(region_id)
);
CREATE INDEX idx_ville_region ON ville(region_id);

-- ----------------------------------------------------------------
-- Hiérarchie organisationnelle des employés (5 niveaux)
-- ----------------------------------------------------------------
CREATE TABLE org_pays (
    org_pays_id    SMALLSERIAL PRIMARY KEY,
    nom_org_pays   VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE org_compagnie (
    org_compagnie_id   SERIAL PRIMARY KEY,
    nom_org_compagnie  VARCHAR(100) NOT NULL,
    org_pays_id        SMALLINT     NOT NULL REFERENCES org_pays(org_pays_id),
    UNIQUE (nom_org_compagnie, org_pays_id)
);

CREATE TABLE org_departement (
    org_departement_id   SERIAL PRIMARY KEY,
    nom_org_departement  VARCHAR(100) NOT NULL,
    org_compagnie_id     INT          NOT NULL REFERENCES org_compagnie(org_compagnie_id),
    UNIQUE (nom_org_departement, org_compagnie_id)
);

CREATE TABLE org_section (
    org_section_id      SERIAL PRIMARY KEY,
    nom_org_section     VARCHAR(100) NOT NULL,
    org_departement_id  INT          NOT NULL REFERENCES org_departement(org_departement_id),
    UNIQUE (nom_org_section, org_departement_id)
);

CREATE TABLE org_groupe (
    org_groupe_id    SERIAL PRIMARY KEY,
    nom_org_groupe   VARCHAR(100) NOT NULL,
    org_section_id   INT          NOT NULL REFERENCES org_section(org_section_id),
    UNIQUE (nom_org_groupe, org_section_id)
);

-- ----------------------------------------------------------------
-- Employés
-- ----------------------------------------------------------------
CREATE TABLE employe (
    employe_id     BIGSERIAL PRIMARY KEY,
    nom            VARCHAR(80)   NOT NULL,
    prenom         VARCHAR(80)   NOT NULL,
    sexe           CHAR(1)       NOT NULL CHECK (sexe IN ('M','F')),
    date_naissance DATE          NOT NULL,
    date_embauche  DATE          NOT NULL,
    date_depart    DATE,
    salaire        NUMERIC(12,2) NOT NULL CHECK (salaire >= 0),
    manager_id     BIGINT        REFERENCES employe(employe_id),
    org_groupe_id  INT           NOT NULL REFERENCES org_groupe(org_groupe_id),
    rue            VARCHAR(200),
    ville_id       INT           REFERENCES ville(ville_id),
    maj_le         TIMESTAMP     NOT NULL DEFAULT now()
);
CREATE INDEX idx_employe_org_groupe ON employe(org_groupe_id);
CREATE INDEX idx_employe_manager    ON employe(manager_id);

CREATE TABLE contrat_employe (
    contrat_id    BIGSERIAL    PRIMARY KEY,
    employe_id    BIGINT       NOT NULL REFERENCES employe(employe_id) ON DELETE CASCADE,
    date_debut    DATE         NOT NULL,
    date_fin      DATE,
    type_contrat  VARCHAR(30)  NOT NULL
                    CHECK (type_contrat IN ('CDI','CDD','Interim','Stage','Alternance','Freelance')),
    CHECK (date_fin IS NULL OR date_fin >= date_debut)
);
CREATE INDEX idx_contrat_employe_employe ON contrat_employe(employe_id, date_debut DESC);

-- ----------------------------------------------------------------
-- Hiérarchie produit (4 niveaux) + fournisseurs
-- ----------------------------------------------------------------
CREATE TABLE fournisseur (
    fournisseur_id    SERIAL PRIMARY KEY,
    nom_fournisseur   VARCHAR(120) NOT NULL,
    pays_id           INT NOT NULL REFERENCES pays(pays_id)
);

CREATE TABLE ligne_produit (
    ligne_produit_id   SERIAL PRIMARY KEY,
    nom_ligne_produit  VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE categorie_produit (
    categorie_produit_id   SERIAL PRIMARY KEY,
    nom_categorie_produit  VARCHAR(100) NOT NULL,
    ligne_produit_id       INT NOT NULL REFERENCES ligne_produit(ligne_produit_id),
    UNIQUE (nom_categorie_produit, ligne_produit_id)
);

CREATE TABLE groupe_produit (
    groupe_produit_id      SERIAL PRIMARY KEY,
    nom_groupe_produit     VARCHAR(100) NOT NULL,
    categorie_produit_id   INT NOT NULL REFERENCES categorie_produit(categorie_produit_id),
    UNIQUE (nom_groupe_produit, categorie_produit_id)
);

CREATE TABLE produit (
    produit_id         BIGSERIAL PRIMARY KEY,
    nom_produit        VARCHAR(150) NOT NULL,
    groupe_produit_id  INT     NOT NULL REFERENCES groupe_produit(groupe_produit_id),
    fournisseur_id     INT     NOT NULL REFERENCES fournisseur(fournisseur_id),
    actif              BOOLEAN NOT NULL DEFAULT TRUE,
    cree_le            DATE    NOT NULL DEFAULT CURRENT_DATE
);
CREATE INDEX idx_produit_groupe      ON produit(groupe_produit_id);
CREATE INDEX idx_produit_fournisseur ON produit(fournisseur_id);

-- Historique des prix : on cherche (produit_id, date) -> (cout, prix_vente)
CREATE TABLE historique_prix (
    prix_id      BIGSERIAL    PRIMARY KEY,
    produit_id   BIGINT       NOT NULL REFERENCES produit(produit_id) ON DELETE CASCADE,
    date_debut   DATE         NOT NULL,
    date_fin     DATE,
    cout         NUMERIC(12,2) NOT NULL CHECK (cout >= 0),
    prix_vente   NUMERIC(12,2) NOT NULL CHECK (prix_vente >= 0),
    CHECK (date_fin IS NULL OR date_fin >= date_debut)
);
CREATE INDEX idx_historique_prix_periode
    ON historique_prix(produit_id, date_debut, date_fin);

-- Remises ponctuelles
CREATE TABLE remise_produit (
    remise_id    BIGSERIAL PRIMARY KEY,
    produit_id   BIGINT       NOT NULL REFERENCES produit(produit_id) ON DELETE CASCADE,
    date_debut   DATE         NOT NULL,
    date_fin     DATE         NOT NULL,
    pct_remise   NUMERIC(5,4) NOT NULL CHECK (pct_remise BETWEEN 0 AND 1),
    CHECK (date_fin >= date_debut)
);
CREATE INDEX idx_remise_periode
    ON remise_produit(produit_id, date_debut, date_fin);

-- ----------------------------------------------------------------
-- Clients
-- ----------------------------------------------------------------
CREATE TABLE groupe_client (
    groupe_client_id   SERIAL PRIMARY KEY,
    nom_groupe_client  VARCHAR(80) NOT NULL UNIQUE,
    description        VARCHAR(255)
);

CREATE TABLE client (
    client_id          BIGSERIAL PRIMARY KEY,
    nom                VARCHAR(80) NOT NULL,
    prenom             VARCHAR(80) NOT NULL,
    sexe               CHAR(1) CHECK (sexe IN ('M','F')),
    date_naissance     DATE,
    groupe_client_id   INT REFERENCES groupe_client(groupe_client_id),
    rue                VARCHAR(200),
    ville_id           INT NOT NULL REFERENCES ville(ville_id),
    actif              BOOLEAN NOT NULL DEFAULT TRUE,
    cree_le            DATE NOT NULL DEFAULT CURRENT_DATE,
    maj_le             TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_client_ville  ON client(ville_id);
CREATE INDEX idx_client_groupe ON client(groupe_client_id);

CREATE TABLE carte_fidelite (
    carte_fidelite_id  BIGSERIAL PRIMARY KEY,
    client_id          BIGINT      NOT NULL UNIQUE REFERENCES client(client_id) ON DELETE CASCADE,
    numero_carte       VARCHAR(20) NOT NULL UNIQUE,
    date_emission      DATE        NOT NULL,
    nom_programme      VARCHAR(50) NOT NULL DEFAULT 'Orion Star Club'
);

-- ----------------------------------------------------------------
-- Canaux de vente
-- ----------------------------------------------------------------
CREATE TABLE canal_vente (
    canal_id     SMALLSERIAL PRIMARY KEY,
    code_canal   VARCHAR(20) NOT NULL UNIQUE,
    nom_canal    VARCHAR(50) NOT NULL
);

-- ----------------------------------------------------------------
-- Commandes
-- ----------------------------------------------------------------
CREATE TABLE commande (
    commande_id    BIGSERIAL PRIMARY KEY,
    date_commande  DATE NOT NULL,
    client_id      BIGINT   NOT NULL REFERENCES client(client_id),
    employe_id     BIGINT   NOT NULL REFERENCES employe(employe_id),
    canal_id       SMALLINT NOT NULL REFERENCES canal_vente(canal_id),
    montant_total  NUMERIC(14,2) NOT NULL DEFAULT 0,
    cree_le        TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_commande_date    ON commande(date_commande);
CREATE INDEX idx_commande_client  ON commande(client_id);
CREATE INDEX idx_commande_employe ON commande(employe_id);

CREATE TABLE ligne_commande (
    commande_id     BIGINT       NOT NULL REFERENCES commande(commande_id) ON DELETE CASCADE,
    numero_ligne    SMALLINT     NOT NULL,
    produit_id      BIGINT       NOT NULL REFERENCES produit(produit_id),
    quantite        NUMERIC(12,3) NOT NULL CHECK (quantite > 0),
    prix_unitaire   NUMERIC(12,2) NOT NULL CHECK (prix_unitaire >= 0),
    cout_unitaire   NUMERIC(12,2) NOT NULL CHECK (cout_unitaire >= 0),
    pct_remise      NUMERIC(5,4)  NOT NULL DEFAULT 0
                    CHECK (pct_remise BETWEEN 0 AND 1),
    PRIMARY KEY (commande_id, numero_ligne)
);
CREATE INDEX idx_ligne_commande_produit ON ligne_commande(produit_id);

-- ----------------------------------------------------------------
-- Vue pratique : prix courant à une date donnée
-- ----------------------------------------------------------------
CREATE OR REPLACE VIEW v_prix_produit_a AS
SELECT hp.produit_id,
       hp.date_debut,
       hp.date_fin,
       hp.cout,
       hp.prix_vente
FROM   historique_prix hp;

COMMENT ON SCHEMA ops IS 'Orion OLTP — modèle opérationnel 3NF (nomenclature française)';
