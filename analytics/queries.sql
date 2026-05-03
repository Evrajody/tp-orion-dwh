-- =============================================================================
-- TP1 — Réponses aux questions analytiques posées par la société Orion
-- À exécuter sur orion_dwh (schéma dw, nomenclature française).
--
-- Conventions :
--   * "Chiffre d'affaires" = SUM(montant_net)
--   * "Marge"              = SUM(montant_marge)
--   * "Quantité"           = SUM(quantite)
-- =============================================================================
SET search_path TO dw, public;

-- -----------------------------------------------------------------------------
-- Q1. Quels sont les produits qui se vendent le mieux ?
-- (top 20 par quantité totale, toutes années confondues)
-- -----------------------------------------------------------------------------
SELECT  p.produit_id,
        p.nom_produit,
        p.nom_groupe_produit,
        SUM(f.quantite)    AS qte_totale,
        SUM(f.montant_net) AS ca
FROM    fait_ventes f
JOIN    dim_produit p USING (cle_produit)
GROUP BY p.produit_id, p.nom_produit, p.nom_groupe_produit
ORDER BY qte_totale DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- Q2. Quels sont les produits en perte de vitesse ?
-- (variation négative de CA entre l'année N-1 et N, top descente)
-- -----------------------------------------------------------------------------
WITH annuel AS (
    SELECT  p.produit_id, p.nom_produit,
            d.annee,
            SUM(f.montant_net) AS ca
    FROM    fait_ventes f
    JOIN    dim_produit p USING (cle_produit)
    JOIN    dim_date    d USING (cle_date)
    GROUP BY p.produit_id, p.nom_produit, d.annee
),
delta AS (
    SELECT  produit_id, nom_produit, annee, ca,
            LAG(ca) OVER (PARTITION BY produit_id ORDER BY annee) AS ca_precedent
    FROM    annuel
)
SELECT  produit_id, nom_produit, annee,
        ca, ca_precedent,
        ca - ca_precedent AS delta_abs,
        CASE WHEN ca_precedent > 0
             THEN ROUND(100 * (ca - ca_precedent) / ca_precedent, 2)
        END AS delta_pct
FROM    delta
WHERE   ca_precedent IS NOT NULL
   AND  ca < ca_precedent
ORDER BY delta_pct ASC NULLS LAST
LIMIT 20;

-- -----------------------------------------------------------------------------
-- Q3. Produits qui contribuent très peu au CA pour un pays/année donnés
-- (paramètres :pays, :annee — ici France 2002)
-- -----------------------------------------------------------------------------
WITH base AS (
    SELECT  p.produit_id, p.nom_produit,
            SUM(f.montant_net) AS ca
    FROM    fait_ventes f
    JOIN    dim_produit    p USING (cle_produit)
    JOIN    dim_geographie g ON g.cle_geographie = f.cle_geographie_client
    JOIN    dim_date       d USING (cle_date)
    WHERE   g.nom_pays = 'France'        -- <<< paramètre :pays
      AND   d.annee     = 2002           -- <<< paramètre :annee
    GROUP BY p.produit_id, p.nom_produit
),
total AS (SELECT SUM(ca) AS tot FROM base)
SELECT  b.produit_id, b.nom_produit,
        b.ca,
        ROUND(100 * b.ca / NULLIF(t.tot, 0), 4) AS pct_ca
FROM    base b CROSS JOIN total t
WHERE   b.ca / NULLIF(t.tot, 0) < 0.001          -- < 0,1 % du CA pays/année
ORDER BY pct_ca ASC;
-- → la même requête sert ensuite à décider d'une remise commerciale.

-- -----------------------------------------------------------------------------
-- Q4. Marge générée par groupe de produit, par année (paramètre :groupe)
-- -----------------------------------------------------------------------------
SELECT  p.nom_groupe_produit,
        d.annee,
        SUM(f.montant_net)    AS ca,
        SUM(f.montant_cout)   AS cout_marchandises,
        SUM(f.montant_marge)  AS marge,
        ROUND(100 * SUM(f.montant_marge) / NULLIF(SUM(f.montant_net), 0), 2) AS pct_marge
FROM    fait_ventes f
JOIN    dim_produit p USING (cle_produit)
JOIN    dim_date    d USING (cle_date)
WHERE   p.nom_groupe_produit = 'Premium — Randonnée'  -- <<< paramètre :groupe
GROUP BY p.nom_groupe_produit, d.annee
ORDER BY d.annee;

-- -----------------------------------------------------------------------------
-- Q5. La marge dépend-elle de la quantité vendue ?
-- (corrélation marge ~ quantité, par produit)
-- -----------------------------------------------------------------------------
WITH par_produit AS (
    SELECT  p.produit_id,
            SUM(f.quantite)      AS qte,
            SUM(f.montant_marge) AS marge
    FROM    fait_ventes f
    JOIN    dim_produit p USING (cle_produit)
    GROUP BY p.produit_id
)
SELECT  CORR(qte, marge)               AS pearson_qte_marge,
        REGR_SLOPE(marge, qte)         AS pente,
        REGR_INTERCEPT(marge, qte)     AS ordonnee_origine,
        REGR_R2(marge, qte)            AS r_carre
FROM    par_produit;

-- -----------------------------------------------------------------------------
-- Q6 & Q7. Les remises font-elles augmenter les ventes ? la marge ?
-- (compare les lignes avec / sans remise)
-- -----------------------------------------------------------------------------
SELECT  CASE WHEN pct_remise > 0 THEN 'avec_remise' ELSE 'sans_remise' END AS bucket,
        COUNT(*)                                  AS nb_lignes,
        ROUND(AVG(quantite)::numeric,        3)   AS qte_moy_ligne,
        ROUND(AVG(montant_net)::numeric,     2)   AS ca_moy_ligne,
        ROUND(AVG(montant_marge)::numeric,   2)   AS marge_moy_ligne,
        ROUND(SUM(montant_net)::numeric,     2)   AS ca_total,
        ROUND(SUM(montant_marge)::numeric,   2)   AS marge_totale
FROM    fait_ventes
GROUP BY 1;

-- -----------------------------------------------------------------------------
-- Q8. Commerciaux qui font le plus de ventes
-- -----------------------------------------------------------------------------
SELECT  e.employe_id, e.nom_complet, e.org_pays,
        COUNT(DISTINCT f.commande_id) AS nb_commandes,
        SUM(f.montant_net)            AS ca,
        SUM(f.montant_marge)          AS marge
FROM    fait_ventes f
JOIN    dim_employe e ON e.cle_employe = f.cle_employe
WHERE   e.est_courant
GROUP BY e.employe_id, e.nom_complet, e.org_pays
ORDER BY ca DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- Q9. Commerciaux les plus performants par pays / sexe / âge / salaire
-- -----------------------------------------------------------------------------
WITH base AS (
    SELECT  e.employe_id, e.nom_complet, e.org_pays,
            e.sexe, e.tranche_age, e.tranche_salaire,
            SUM(f.montant_net) AS ca
    FROM    fait_ventes f
    JOIN    dim_employe e ON e.cle_employe = f.cle_employe
    WHERE   e.est_courant
    GROUP BY e.employe_id, e.nom_complet, e.org_pays,
             e.sexe, e.tranche_age, e.tranche_salaire
)
SELECT  org_pays, sexe, tranche_age, tranche_salaire,
        employe_id, nom_complet, ca,
        ROW_NUMBER() OVER (PARTITION BY org_pays         ORDER BY ca DESC) AS rang_pays,
        ROW_NUMBER() OVER (PARTITION BY sexe             ORDER BY ca DESC) AS rang_sexe,
        ROW_NUMBER() OVER (PARTITION BY tranche_age      ORDER BY ca DESC) AS rang_age,
        ROW_NUMBER() OVER (PARTITION BY tranche_salaire  ORDER BY ca DESC) AS rang_salaire
FROM    base
ORDER BY ca DESC;

-- -----------------------------------------------------------------------------
-- Q10. Quels groupes de clients sont identifiés ?
-- -----------------------------------------------------------------------------
SELECT  c.groupe_client,
        COUNT(DISTINCT c.client_id)            AS nb_clients,
        SUM(f.montant_net)                     AS ca,
        ROUND(AVG(f.montant_net)::numeric, 2)  AS panier_moyen_ligne
FROM    fait_ventes f
JOIN    dim_client c ON c.cle_client = f.cle_client
WHERE   c.est_courant
GROUP BY c.groupe_client
ORDER BY ca DESC;

-- -----------------------------------------------------------------------------
-- Q11. Clients les plus rentables (top 50)
-- -----------------------------------------------------------------------------
SELECT  c.client_id, c.nom_complet, c.nom_pays,
        SUM(f.montant_net)             AS ca,
        SUM(f.montant_marge)           AS marge,
        COUNT(DISTINCT f.commande_id)  AS nb_commandes
FROM    fait_ventes f
JOIN    dim_client c ON c.cle_client = f.cle_client
WHERE   c.est_courant
GROUP BY c.client_id, c.nom_complet, c.nom_pays
ORDER BY marge DESC
LIMIT 50;

-- -----------------------------------------------------------------------------
-- Q12. Fournisseurs qui proposent les produits les plus rentables
-- -----------------------------------------------------------------------------
SELECT  s.fournisseur_id, s.nom_fournisseur, s.nom_pays,
        SUM(f.montant_net)    AS ca,
        SUM(f.montant_marge)  AS marge,
        ROUND(100 * SUM(f.montant_marge) / NULLIF(SUM(f.montant_net), 0), 2) AS taux_marge
FROM    fait_ventes f
JOIN    dim_fournisseur s USING (cle_fournisseur)
GROUP BY s.fournisseur_id, s.nom_fournisseur, s.nom_pays
ORDER BY marge DESC
LIMIT 20;

-- -----------------------------------------------------------------------------
-- Q13. Moyenne et écart-type du CA (par commande, par mois, par employé)
-- -----------------------------------------------------------------------------
WITH par_commande AS (
    SELECT commande_id, SUM(montant_net) AS ca
    FROM   fait_ventes GROUP BY commande_id
)
SELECT  AVG(ca)         AS ca_moy_commande,
        STDDEV_SAMP(ca) AS ca_std_commande,
        MIN(ca)         AS ca_min,
        MAX(ca)         AS ca_max
FROM    par_commande;

WITH par_mois AS (
    SELECT d.annee, d.numero_mois, SUM(f.montant_net) AS ca
    FROM   fait_ventes f JOIN dim_date d USING (cle_date)
    GROUP BY d.annee, d.numero_mois
)
SELECT  AVG(ca) AS ca_moy_mois, STDDEV_SAMP(ca) AS ca_std_mois FROM par_mois;

WITH par_employe AS (
    SELECT e.employe_id, SUM(f.montant_net) AS ca
    FROM   fait_ventes f JOIN dim_employe e ON e.cle_employe = f.cle_employe
    WHERE  e.est_courant
    GROUP BY e.employe_id
)
SELECT  AVG(ca) AS ca_moy_employe, STDDEV_SAMP(ca) AS ca_std_employe FROM par_employe;

-- -----------------------------------------------------------------------------
-- Q14. Variables qui expliquent le mieux le CA (η² par variable candidate)
-- -----------------------------------------------------------------------------
WITH faits AS (
    SELECT  f.montant_net,
            p.nom_ligne_produit,
            p.nom_categorie_produit,
            c.groupe_client,
            ch.code_canal,
            e.sexe                AS sexe_emp,
            e.tranche_salaire     AS tranche_salaire_emp,
            g.nom_pays            AS pays_client
    FROM    fait_ventes    f
    JOIN    dim_produit    p  USING (cle_produit)
    JOIN    dim_client     c  ON c.cle_client = f.cle_client
    JOIN    dim_canal      ch USING (cle_canal)
    JOIN    dim_employe    e  ON e.cle_employe = f.cle_employe
    JOIN    dim_geographie g  ON g.cle_geographie = f.cle_geographie_client
),
mu_t AS (SELECT AVG(montant_net) AS m_t FROM faits),
sst  AS (SELECT SUM(power(montant_net - m_t, 2)) AS st FROM faits, mu_t),
eta(variable, eta_carre) AS (
    SELECT 'ligne_produit', (
        SELECT SUM(n_g * power(m_g - m_t, 2)) / NULLIF(st, 0)
        FROM (SELECT nom_ligne_produit AS lvl, AVG(montant_net) AS m_g, COUNT(*) AS n_g
              FROM faits GROUP BY nom_ligne_produit) g, mu_t, sst)
    UNION ALL SELECT 'categorie_produit', (
        SELECT SUM(n_g * power(m_g - m_t, 2)) / NULLIF(st, 0)
        FROM (SELECT nom_categorie_produit AS lvl, AVG(montant_net) AS m_g, COUNT(*) AS n_g
              FROM faits GROUP BY nom_categorie_produit) g, mu_t, sst)
    UNION ALL SELECT 'groupe_client', (
        SELECT SUM(n_g * power(m_g - m_t, 2)) / NULLIF(st, 0)
        FROM (SELECT groupe_client AS lvl, AVG(montant_net) AS m_g, COUNT(*) AS n_g
              FROM faits GROUP BY groupe_client) g, mu_t, sst)
    UNION ALL SELECT 'canal', (
        SELECT SUM(n_g * power(m_g - m_t, 2)) / NULLIF(st, 0)
        FROM (SELECT code_canal AS lvl, AVG(montant_net) AS m_g, COUNT(*) AS n_g
              FROM faits GROUP BY code_canal) g, mu_t, sst)
    UNION ALL SELECT 'sexe_emp', (
        SELECT SUM(n_g * power(m_g - m_t, 2)) / NULLIF(st, 0)
        FROM (SELECT sexe_emp AS lvl, AVG(montant_net) AS m_g, COUNT(*) AS n_g
              FROM faits GROUP BY sexe_emp) g, mu_t, sst)
    UNION ALL SELECT 'tranche_salaire_emp', (
        SELECT SUM(n_g * power(m_g - m_t, 2)) / NULLIF(st, 0)
        FROM (SELECT tranche_salaire_emp AS lvl, AVG(montant_net) AS m_g, COUNT(*) AS n_g
              FROM faits GROUP BY tranche_salaire_emp) g, mu_t, sst)
    UNION ALL SELECT 'pays_client', (
        SELECT SUM(n_g * power(m_g - m_t, 2)) / NULLIF(st, 0)
        FROM (SELECT pays_client AS lvl, AVG(montant_net) AS m_g, COUNT(*) AS n_g
              FROM faits GROUP BY pays_client) g, mu_t, sst)
)
SELECT variable, ROUND(eta_carre::numeric, 4) AS eta_carre
FROM   eta
ORDER BY eta_carre DESC NULLS LAST;

-- -----------------------------------------------------------------------------
-- Q15. Différence significative de CA entre commerciaux F vs M (test de Welch)
-- -----------------------------------------------------------------------------
WITH par_emp AS (
    SELECT e.sexe, e.employe_id, SUM(f.montant_net) AS ca
    FROM   fait_ventes f JOIN dim_employe e ON e.cle_employe = f.cle_employe
    WHERE  e.est_courant
    GROUP BY e.sexe, e.employe_id
),
agg AS (
    SELECT  sexe,
            COUNT(*)         AS n,
            AVG(ca)          AS ca_moy,
            VAR_SAMP(ca)     AS ca_var
    FROM    par_emp
    GROUP BY sexe
)
SELECT  f.ca_moy AS ca_moy_F, m.ca_moy AS ca_moy_M,
        f.n      AS n_F,      m.n      AS n_M,
        (f.ca_moy - m.ca_moy)
        / sqrt(f.ca_var / f.n + m.ca_var / m.n) AS welch_t
FROM    (SELECT * FROM agg WHERE sexe = 'F') f
CROSS JOIN
        (SELECT * FROM agg WHERE sexe = 'M') m;
