-- ================================================================
--  Données de référence statiques (chargées au démarrage du conteneur)
-- ================================================================
SET search_path TO ops, public;

INSERT INTO continent (nom_continent) VALUES
  ('Amérique du Nord'), ('Amérique du Sud'), ('Europe'),
  ('Asie'), ('Afrique'), ('Océanie')
ON CONFLICT DO NOTHING;

-- Pays utilisés par l'énoncé + quelques autres pour les fournisseurs
INSERT INTO pays (code_pays, nom_pays, continent_id) VALUES
  ('US', 'États-Unis',   (SELECT continent_id FROM continent WHERE nom_continent = 'Amérique du Nord')),
  ('CA', 'Canada',       (SELECT continent_id FROM continent WHERE nom_continent = 'Amérique du Nord')),
  ('BE', 'Belgique',     (SELECT continent_id FROM continent WHERE nom_continent = 'Europe')),
  ('NL', 'Pays-Bas',     (SELECT continent_id FROM continent WHERE nom_continent = 'Europe')),
  ('DE', 'Allemagne',    (SELECT continent_id FROM continent WHERE nom_continent = 'Europe')),
  ('GB', 'Royaume-Uni',  (SELECT continent_id FROM continent WHERE nom_continent = 'Europe')),
  ('DK', 'Danemark',     (SELECT continent_id FROM continent WHERE nom_continent = 'Europe')),
  ('FR', 'France',       (SELECT continent_id FROM continent WHERE nom_continent = 'Europe')),
  ('IT', 'Italie',       (SELECT continent_id FROM continent WHERE nom_continent = 'Europe')),
  ('ES', 'Espagne',      (SELECT continent_id FROM continent WHERE nom_continent = 'Europe')),
  ('AU', 'Australie',    (SELECT continent_id FROM continent WHERE nom_continent = 'Océanie')),
  ('CN', 'Chine',        (SELECT continent_id FROM continent WHERE nom_continent = 'Asie')),
  ('JP', 'Japon',        (SELECT continent_id FROM continent WHERE nom_continent = 'Asie')),
  ('IN', 'Inde',         (SELECT continent_id FROM continent WHERE nom_continent = 'Asie')),
  ('BR', 'Brésil',       (SELECT continent_id FROM continent WHERE nom_continent = 'Amérique du Sud')),
  ('ZA', 'Afrique du Sud',(SELECT continent_id FROM continent WHERE nom_continent = 'Afrique'))
ON CONFLICT (code_pays) DO NOTHING;

INSERT INTO canal_vente (code_canal, nom_canal) VALUES
  ('MAGASIN',  'Magasin physique'),
  ('CATALOGUE','Vente par catalogue'),
  ('INTERNET', 'Vente en ligne')
ON CONFLICT (code_canal) DO NOTHING;

-- Hiérarchie organisationnelle minimale (filiales pays = celles du brief)
INSERT INTO org_pays (nom_org_pays) VALUES
  ('Siège USA'), ('Belgique'), ('Pays-Bas'), ('Allemagne'),
  ('Royaume-Uni'), ('Danemark'), ('France'), ('Italie'),
  ('Espagne'), ('Australie')
ON CONFLICT DO NOTHING;

-- Une compagnie unique par pays (Orion <PAYS>)
INSERT INTO org_compagnie (nom_org_compagnie, org_pays_id)
SELECT 'Orion ' || nom_org_pays, org_pays_id FROM org_pays
ON CONFLICT DO NOTHING;

-- Départements typiques
INSERT INTO org_departement (nom_org_departement, org_compagnie_id)
SELECT d, c.org_compagnie_id
FROM   org_compagnie c,
       (VALUES ('Ventes'),('Marketing'),('Finance'),
               ('Informatique'),('Ressources Humaines'),('Logistique')) AS x(d)
ON CONFLICT DO NOTHING;

-- Sections (1 par département)
INSERT INTO org_section (nom_org_section, org_departement_id)
SELECT 'Section ' || nom_org_departement, org_departement_id
FROM   org_departement
ON CONFLICT DO NOTHING;

-- Groupes (2 par section : Groupe A et Groupe B)
INSERT INTO org_groupe (nom_org_groupe, org_section_id)
SELECT 'Groupe A — ' || nom_org_section, org_section_id FROM org_section
ON CONFLICT DO NOTHING;
INSERT INTO org_groupe (nom_org_groupe, org_section_id)
SELECT 'Groupe B — ' || nom_org_section, org_section_id FROM org_section
ON CONFLICT DO NOTHING;

-- Lignes / catégories / groupes produits (Orion = sport et plein air)
INSERT INTO ligne_produit (nom_ligne_produit) VALUES
  ('Plein air'),
  ('Sports collectifs'),
  ('Forme & fitness'),
  ('Vêtements'),
  ('Chaussures')
ON CONFLICT DO NOTHING;

INSERT INTO categorie_produit (nom_categorie_produit, ligne_produit_id)
SELECT cat, lp.ligne_produit_id
FROM ligne_produit lp
JOIN (VALUES
  ('Plein air',         'Camping'),
  ('Plein air',         'Randonnée'),
  ('Plein air',         'Cyclisme'),
  ('Sports collectifs', 'Football'),
  ('Sports collectifs', 'Basketball'),
  ('Sports collectifs', 'Tennis'),
  ('Forme & fitness',   'Yoga'),
  ('Forme & fitness',   'Musculation'),
  ('Vêtements',         'Hommes'),
  ('Vêtements',         'Femmes'),
  ('Chaussures',        'Course'),
  ('Chaussures',        'Trail')
) AS m(ligne, cat) ON m.ligne = lp.nom_ligne_produit
ON CONFLICT DO NOTHING;

-- Groupes produit : 2 par catégorie (Entrée de gamme / Premium)
INSERT INTO groupe_produit (nom_groupe_produit, categorie_produit_id)
SELECT 'Entrée — ' || nom_categorie_produit, categorie_produit_id
FROM categorie_produit
ON CONFLICT DO NOTHING;
INSERT INTO groupe_produit (nom_groupe_produit, categorie_produit_id)
SELECT 'Premium — ' || nom_categorie_produit, categorie_produit_id
FROM categorie_produit
ON CONFLICT DO NOTHING;

INSERT INTO groupe_client (nom_groupe_client, description) VALUES
  ('Bronze',  'Client occasionnel'),
  ('Argent',  'Client régulier'),
  ('Or',      'Client fidèle'),
  ('VIP',     'Très haut panier'),
  ('Inactif', 'Pas d''achat depuis plus de 18 mois')
ON CONFLICT DO NOTHING;
