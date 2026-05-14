-- ============================================================================
-- 03 -- Donnees de reference statiques pour OrionOLTP.
-- A executer dans : OrionOLTP
-- Pre-requis      : script 02 execute.
-- Verification    : SELECT (SELECT COUNT(*) FROM ops.continent) AS continents,
--                          (SELECT COUNT(*) FROM ops.pays)      AS pays,
--                          (SELECT COUNT(*) FROM ops.canal_vente) AS canaux,
--                          (SELECT COUNT(*) FROM ops.org_pays)  AS org_pays,
--                          (SELECT COUNT(*) FROM ops.ligne_produit) AS lignes;
-- ============================================================================
USE OrionOLTP;
GO

-- ----------------------------------------------------------------------------
-- Continents (6)
-- ----------------------------------------------------------------------------
INSERT INTO ops.continent (nom_continent) VALUES
  (N'Amerique du Nord'),
  (N'Amerique du Sud'),
  (N'Europe'),
  (N'Asie'),
  (N'Afrique'),
  (N'Oceanie');
GO

-- ----------------------------------------------------------------------------
-- Pays (16) : ceux de l'enonce + quelques autres pour les fournisseurs
-- ----------------------------------------------------------------------------
INSERT INTO ops.pays (code_pays, nom_pays, continent_id) VALUES
  ('US', N'Etats-Unis',     (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Amerique du Nord')),
  ('CA', N'Canada',         (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Amerique du Nord')),
  ('BE', N'Belgique',       (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Europe')),
  ('NL', N'Pays-Bas',       (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Europe')),
  ('DE', N'Allemagne',      (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Europe')),
  ('GB', N'Royaume-Uni',    (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Europe')),
  ('DK', N'Danemark',       (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Europe')),
  ('FR', N'France',         (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Europe')),
  ('IT', N'Italie',         (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Europe')),
  ('ES', N'Espagne',        (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Europe')),
  ('AU', N'Australie',      (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Oceanie')),
  ('CN', N'Chine',          (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Asie')),
  ('JP', N'Japon',          (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Asie')),
  ('IN', N'Inde',           (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Asie')),
  ('BR', N'Bresil',         (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Amerique du Sud')),
  ('ZA', N'Afrique du Sud', (SELECT continent_id FROM ops.continent WHERE nom_continent = N'Afrique'));
GO

-- ----------------------------------------------------------------------------
-- Canaux de vente (3)
-- ----------------------------------------------------------------------------
INSERT INTO ops.canal_vente (code_canal, nom_canal) VALUES
  (N'MAGASIN',  N'Magasin physique'),
  (N'CATALOGUE',N'Vente par catalogue'),
  (N'INTERNET', N'Vente en ligne');
GO

-- ----------------------------------------------------------------------------
-- Hierarchie organisationnelle (10 pays org)
-- ----------------------------------------------------------------------------
INSERT INTO ops.org_pays (nom_org_pays) VALUES
  (N'Siege USA'), (N'Belgique'), (N'Pays-Bas'), (N'Allemagne'),
  (N'Royaume-Uni'), (N'Danemark'), (N'France'), (N'Italie'),
  (N'Espagne'), (N'Australie');
GO

-- 1 compagnie par pays org
INSERT INTO ops.org_compagnie (nom_org_compagnie, org_pays_id)
SELECT N'Orion ' + nom_org_pays, org_pays_id FROM ops.org_pays;
GO

-- 6 departements par compagnie
INSERT INTO ops.org_departement (nom_org_departement, org_compagnie_id)
SELECT d, c.org_compagnie_id
  FROM ops.org_compagnie c
 CROSS JOIN (VALUES (N'Ventes'),(N'Marketing'),(N'Finance'),
                    (N'Informatique'),(N'Ressources Humaines'),
                    (N'Logistique')) AS x(d);
GO

-- 1 section par departement
INSERT INTO ops.org_section (nom_org_section, org_departement_id)
SELECT N'Section ' + nom_org_departement, org_departement_id
  FROM ops.org_departement;
GO

-- 2 groupes par section (Groupe A et Groupe B)
INSERT INTO ops.org_groupe (nom_org_groupe, org_section_id)
SELECT N'Groupe A -- ' + nom_org_section, org_section_id FROM ops.org_section;
INSERT INTO ops.org_groupe (nom_org_groupe, org_section_id)
SELECT N'Groupe B -- ' + nom_org_section, org_section_id FROM ops.org_section;
GO

-- ----------------------------------------------------------------------------
-- Hierarchie produit
-- ----------------------------------------------------------------------------
INSERT INTO ops.ligne_produit (nom_ligne_produit) VALUES
  (N'Plein air'),
  (N'Sports collectifs'),
  (N'Forme et fitness'),
  (N'Vetements'),
  (N'Chaussures');
GO

-- 12 categories
INSERT INTO ops.categorie_produit (nom_categorie_produit, ligne_produit_id)
SELECT cat, lp.ligne_produit_id
FROM ops.ligne_produit lp
JOIN (VALUES
  (N'Plein air',         N'Camping'),
  (N'Plein air',         N'Randonnee'),
  (N'Plein air',         N'Cyclisme'),
  (N'Sports collectifs', N'Football'),
  (N'Sports collectifs', N'Basketball'),
  (N'Sports collectifs', N'Tennis'),
  (N'Forme et fitness',  N'Yoga'),
  (N'Forme et fitness',  N'Musculation'),
  (N'Vetements',         N'Hommes'),
  (N'Vetements',         N'Femmes'),
  (N'Chaussures',        N'Course'),
  (N'Chaussures',        N'Trail')
) AS m(ligne, cat) ON m.ligne = lp.nom_ligne_produit;
GO

-- 2 groupes par categorie (Entree de gamme et Premium)
INSERT INTO ops.groupe_produit (nom_groupe_produit, categorie_produit_id)
SELECT N'Entree -- ' + nom_categorie_produit, categorie_produit_id
  FROM ops.categorie_produit;
INSERT INTO ops.groupe_produit (nom_groupe_produit, categorie_produit_id)
SELECT N'Premium -- ' + nom_categorie_produit, categorie_produit_id
  FROM ops.categorie_produit;
GO

-- ----------------------------------------------------------------------------
-- Groupes clients (5)
-- ----------------------------------------------------------------------------
INSERT INTO ops.groupe_client (nom_groupe_client, description) VALUES
  (N'Bronze',  N'Client occasionnel'),
  (N'Argent',  N'Client regulier'),
  (N'Or',      N'Client fidele'),
  (N'VIP',     N'Tres haut panier'),
  (N'Inactif', N'Pas d''achat depuis plus de 18 mois');
GO

PRINT '[03] OK -- donnees de reference inserees';
PRINT '       6 continents, 16 pays, 3 canaux, 10 org_pays,';
PRINT '       60 departements, 60 sections, 120 groupes,';
PRINT '       5 lignes_produit, 12 categories, 24 groupes_produit,';
PRINT '       5 groupes_client.';
GO
