-- ============================================================================
-- 11 -- Orchestrateur T-SQL (cross-database) -- equivalent voie A.
-- A executer dans : OrionETL
-- Pre-requis      : scripts 01 a 10 executes ; OrionOLTP doit contenir des
--                   donnees operationnelles (commandes, clients, produits).
-- Usage final     : EXEC etl.sp_run_complet;  -- lance l'ETL bout-en-bout.
-- ============================================================================
USE OrionETL;
GO

-- ----------------------------------------------------------------------------
-- sp_charger_staging -- vide le staging puis le recharge depuis OrionOLTP.
-- Utilise INSERT ... SELECT cross-database (OrionOLTP.ops.* -> staging.*).
-- ----------------------------------------------------------------------------
IF OBJECT_ID('etl.sp_charger_staging','P') IS NOT NULL
    DROP PROCEDURE etl.sp_charger_staging;
GO

CREATE PROCEDURE etl.sp_charger_staging
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id BIGINT;
    EXEC etl.sp_run_start @job_name = N'charger_staging', @run_id = @run_id OUTPUT;

    BEGIN TRY
        -- Watermark pour le chargement incremental de lignes_commande
        DECLARE @watermark DATETIME2(3) =
            ISNULL((SELECT last_value FROM etl.watermark WHERE job_name = N'fait_ventes'),
                   '1900-01-01');

        -- =================================================================
        -- staging.geographie_full
        -- =================================================================
        TRUNCATE TABLE staging.geographie_full;

        INSERT staging.geographie_full
            (ville_id, nom_ville, code_postal, nom_region,
             code_pays, nom_pays, nom_continent)
        SELECT v.ville_id, v.nom_ville, v.code_postal,
               r.nom_region,
               p.code_pays, p.nom_pays,
               c.nom_continent
          FROM OrionOLTP.ops.ville     v
          JOIN OrionOLTP.ops.region    r ON r.region_id    = v.region_id
          JOIN OrionOLTP.ops.pays      p ON p.pays_id      = r.pays_id
          JOIN OrionOLTP.ops.continent c ON c.continent_id = p.continent_id;

        -- =================================================================
        -- staging.fournisseur_full
        -- =================================================================
        TRUNCATE TABLE staging.fournisseur_full;

        INSERT staging.fournisseur_full
            (fournisseur_id, nom_fournisseur, nom_pays, nom_continent)
        SELECT f.fournisseur_id, f.nom_fournisseur,
               p.nom_pays, c.nom_continent
          FROM OrionOLTP.ops.fournisseur f
          JOIN OrionOLTP.ops.pays        p ON p.pays_id      = f.pays_id
          JOIN OrionOLTP.ops.continent   c ON c.continent_id = p.continent_id;

        -- =================================================================
        -- staging.canal
        -- =================================================================
        TRUNCATE TABLE staging.canal;

        INSERT staging.canal (canal_id, code_canal, nom_canal)
        SELECT canal_id, code_canal, nom_canal
          FROM OrionOLTP.ops.canal_vente;

        -- =================================================================
        -- staging.produit_full
        -- =================================================================
        TRUNCATE TABLE staging.produit_full;

        INSERT staging.produit_full
            (produit_id, nom_produit, nom_groupe_produit,
             nom_categorie_produit, nom_ligne_produit,
             fournisseur_id_naturel, nom_fournisseur, actif)
        SELECT pr.produit_id, pr.nom_produit,
               g.nom_groupe_produit,
               cat.nom_categorie_produit,
               lp.nom_ligne_produit,
               f.fournisseur_id, f.nom_fournisseur,
               pr.actif
          FROM OrionOLTP.ops.produit            pr
          JOIN OrionOLTP.ops.groupe_produit     g   ON g.groupe_produit_id    = pr.groupe_produit_id
          JOIN OrionOLTP.ops.categorie_produit  cat ON cat.categorie_produit_id = g.categorie_produit_id
          JOIN OrionOLTP.ops.ligne_produit      lp  ON lp.ligne_produit_id    = cat.ligne_produit_id
          JOIN OrionOLTP.ops.fournisseur        f   ON f.fournisseur_id       = pr.fournisseur_id;

        -- =================================================================
        -- staging.client_full
        -- =================================================================
        TRUNCATE TABLE staging.client_full;

        INSERT staging.client_full
            (client_id, nom_complet, sexe, date_naissance,
             groupe_client, a_carte_fidelite,
             nom_ville, nom_pays, nom_continent, maj_le)
        SELECT c.client_id,
               c.nom + N' ' + c.prenom                AS nom_complet,
               c.sexe, c.date_naissance,
               gc.nom_groupe_client                   AS groupe_client,
               CASE WHEN cf.carte_fidelite_id IS NULL THEN 0 ELSE 1 END AS a_carte_fidelite,
               v.nom_ville,
               p.nom_pays,
               cont.nom_continent,
               c.maj_le
          FROM OrionOLTP.ops.client          c
          LEFT JOIN OrionOLTP.ops.groupe_client   gc ON gc.groupe_client_id = c.groupe_client_id
          LEFT JOIN OrionOLTP.ops.carte_fidelite  cf ON cf.client_id        = c.client_id
          JOIN OrionOLTP.ops.ville           v    ON v.ville_id     = c.ville_id
          JOIN OrionOLTP.ops.region          r    ON r.region_id    = v.region_id
          JOIN OrionOLTP.ops.pays            p    ON p.pays_id      = r.pays_id
          JOIN OrionOLTP.ops.continent       cont ON cont.continent_id = p.continent_id;

        -- =================================================================
        -- staging.employe_full (avec contrat courant via OUTER APPLY)
        -- =================================================================
        TRUNCATE TABLE staging.employe_full;

        INSERT staging.employe_full
            (employe_id, nom_complet, sexe, date_naissance, salaire,
             org_pays, org_compagnie, org_departement, org_section, org_groupe,
             nom_manager, date_embauche, date_depart,
             type_contrat_courant, date_debut_contrat, date_fin_contrat,
             statut_contrat, nb_contrats_signes,
             maj_le)
        SELECT e.employe_id,
               e.nom + N' ' + e.prenom              AS nom_complet,
               e.sexe, e.date_naissance, e.salaire,
               op.nom_org_pays                       AS org_pays,
               oc.nom_org_compagnie                  AS org_compagnie,
               od.nom_org_departement                AS org_departement,
               os.nom_org_section                    AS org_section,
               og.nom_org_groupe                     AS org_groupe,
               (m.nom + N' ' + m.prenom)             AS nom_manager,
               e.date_embauche, e.date_depart,
               cc.type_contrat                       AS type_contrat_courant,
               cc.date_debut                         AS date_debut_contrat,
               cc.date_fin                           AS date_fin_contrat,
               CASE
                 WHEN cc.contrat_id IS NULL                                  THEN N'SansContrat'
                 WHEN cc.date_fin   IS NULL                                  THEN N'Actif'
                 WHEN cc.date_fin   >= CAST(SYSUTCDATETIME() AS DATE)        THEN N'Actif'
                 ELSE                                                             N'Expire'
               END                                   AS statut_contrat,
               (SELECT COUNT(*) FROM OrionOLTP.ops.contrat_employe ce
                 WHERE ce.employe_id = e.employe_id) AS nb_contrats_signes,
               e.maj_le
          FROM OrionOLTP.ops.employe          e
          JOIN OrionOLTP.ops.org_groupe       og  ON og.org_groupe_id      = e.org_groupe_id
          JOIN OrionOLTP.ops.org_section      os  ON os.org_section_id     = og.org_section_id
          JOIN OrionOLTP.ops.org_departement  od  ON od.org_departement_id = os.org_departement_id
          JOIN OrionOLTP.ops.org_compagnie    oc  ON oc.org_compagnie_id   = od.org_compagnie_id
          JOIN OrionOLTP.ops.org_pays         op  ON op.org_pays_id        = oc.org_pays_id
          LEFT JOIN OrionOLTP.ops.employe     m   ON m.employe_id          = e.manager_id
          OUTER APPLY (
                SELECT TOP 1 contrat_id, type_contrat, date_debut, date_fin
                  FROM OrionOLTP.ops.contrat_employe ce
                 WHERE ce.employe_id = e.employe_id
                 ORDER BY CASE WHEN ce.date_fin IS NULL THEN 0 ELSE 1 END,
                          ce.date_debut DESC
          ) cc;

        -- =================================================================
        -- staging.lignes_commande (incremental sur watermark)
        -- =================================================================
        TRUNCATE TABLE staging.lignes_commande;

        INSERT staging.lignes_commande
            (commande_id, numero_ligne, date_commande,
             client_id, employe_id, canal_id,
             produit_id, fournisseur_id, cli_ville_id,
             quantite, prix_unitaire, cout_unitaire, pct_remise)
        SELECT o.commande_id, l.numero_ligne, o.date_commande,
               o.client_id, o.employe_id, o.canal_id,
               l.produit_id, p.fournisseur_id,
               c.ville_id   AS cli_ville_id,
               l.quantite, l.prix_unitaire, l.cout_unitaire, l.pct_remise
          FROM OrionOLTP.ops.commande        o
          JOIN OrionOLTP.ops.ligne_commande  l  ON l.commande_id = o.commande_id
          JOIN OrionOLTP.ops.produit         p  ON p.produit_id  = l.produit_id
          JOIN OrionOLTP.ops.client          c  ON c.client_id   = o.client_id
         WHERE CAST(o.date_commande AS DATETIME2(3)) > @watermark;

        DECLARE @rows_in BIGINT = (SELECT COUNT(*) FROM staging.lignes_commande);
        EXEC etl.sp_run_end @run_id, N'SUCCESS', @rows_in, @rows_in;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC etl.sp_run_end @run_id, N'FAIL', NULL, NULL, @err;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- sp_pousser_dwh -- TRUNCATE + INSERT cross-database vers OrionDWH.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('etl.sp_pousser_dwh','P') IS NOT NULL
    DROP PROCEDURE etl.sp_pousser_dwh;
GO

CREATE PROCEDURE etl.sp_pousser_dwh
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id BIGINT;
    EXEC etl.sp_run_start @job_name = N'pousser_dwh', @run_id = @run_id OUTPUT;

    BEGIN TRY
        -- Vidage dans l'ordre inverse des FK (fact d'abord, puis dim)
        TRUNCATE TABLE OrionDWH.dw.fait_ventes;
        DELETE FROM OrionDWH.dw.dim_client;
        DELETE FROM OrionDWH.dw.dim_employe;
        DELETE FROM OrionDWH.dw.dim_produit;
        DELETE FROM OrionDWH.dw.dim_fournisseur;
        DELETE FROM OrionDWH.dw.dim_geographie;
        DELETE FROM OrionDWH.dw.dim_canal;
        DELETE FROM OrionDWH.dw.dim_date;
        DBCC CHECKIDENT ('OrionDWH.dw.dim_client',      RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('OrionDWH.dw.dim_employe',     RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('OrionDWH.dw.dim_produit',     RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('OrionDWH.dw.dim_fournisseur', RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('OrionDWH.dw.dim_geographie',  RESEED, 0) WITH NO_INFOMSGS;
        DBCC CHECKIDENT ('OrionDWH.dw.dim_canal',       RESEED, 0) WITH NO_INFOMSGS;

        -- ----- dim_date (PK non identity, copie directe) ------------------
        INSERT OrionDWH.dw.dim_date
        SELECT * FROM dim.dim_date;

        -- ----- dim_canal --------------------------------------------------
        SET IDENTITY_INSERT OrionDWH.dw.dim_canal ON;
        INSERT OrionDWH.dw.dim_canal (cle_canal, canal_id, code_canal, nom_canal)
        SELECT cle_canal, canal_id, code_canal, nom_canal FROM dim.dim_canal;
        SET IDENTITY_INSERT OrionDWH.dw.dim_canal OFF;

        -- ----- dim_geographie --------------------------------------------
        SET IDENTITY_INSERT OrionDWH.dw.dim_geographie ON;
        INSERT OrionDWH.dw.dim_geographie
            (cle_geographie, ville_id, nom_ville, nom_region,
             code_pays, nom_pays, nom_continent, code_postal)
        SELECT cle_geographie, ville_id, nom_ville, nom_region,
               code_pays, nom_pays, nom_continent, NULL  -- code_postal pas dans dim
          FROM dim.dim_geographie;
        SET IDENTITY_INSERT OrionDWH.dw.dim_geographie OFF;

        -- ----- dim_fournisseur -------------------------------------------
        SET IDENTITY_INSERT OrionDWH.dw.dim_fournisseur ON;
        INSERT OrionDWH.dw.dim_fournisseur
            (cle_fournisseur, fournisseur_id, nom_fournisseur, nom_pays, nom_continent)
        SELECT * FROM dim.dim_fournisseur;
        SET IDENTITY_INSERT OrionDWH.dw.dim_fournisseur OFF;

        -- ----- dim_produit -----------------------------------------------
        SET IDENTITY_INSERT OrionDWH.dw.dim_produit ON;
        INSERT OrionDWH.dw.dim_produit
            (cle_produit, produit_id, nom_produit, nom_groupe_produit,
             nom_categorie_produit, nom_ligne_produit,
             fournisseur_id_naturel, nom_fournisseur, actif, maj_le)
        SELECT * FROM dim.dim_produit;
        SET IDENTITY_INSERT OrionDWH.dw.dim_produit OFF;

        -- ----- dim_client (SCD2) -----------------------------------------
        SET IDENTITY_INSERT OrionDWH.dw.dim_client ON;
        INSERT OrionDWH.dw.dim_client
            (cle_client, client_id, nom_complet, sexe, tranche_age,
             groupe_client, a_carte_fidelite,
             nom_ville, nom_pays, nom_continent,
             effectif_du, effectif_au, est_courant, hash_ligne)
        SELECT * FROM dim.dim_client;
        SET IDENTITY_INSERT OrionDWH.dw.dim_client OFF;

        -- ----- dim_employe (SCD2 + 5 colonnes contrat) -------------------
        SET IDENTITY_INSERT OrionDWH.dw.dim_employe ON;
        INSERT OrionDWH.dw.dim_employe
            (cle_employe, employe_id, nom_complet, sexe, tranche_age,
             salaire, tranche_salaire,
             org_pays, org_compagnie, org_departement, org_section, org_groupe,
             nom_manager, date_embauche, date_depart,
             type_contrat_courant, date_debut_contrat, date_fin_contrat,
             statut_contrat, nb_contrats_signes,
             effectif_du, effectif_au, est_courant, hash_ligne)
        SELECT * FROM dim.dim_employe;
        SET IDENTITY_INSERT OrionDWH.dw.dim_employe OFF;

        -- ----- fact ------------------------------------------------------
        INSERT OrionDWH.dw.fait_ventes
            (cle_date, cle_produit, cle_client, cle_employe,
             cle_fournisseur, cle_canal, cle_geographie_client,
             commande_id, numero_ligne,
             quantite, prix_unitaire, cout_unitaire, pct_remise,
             montant_brut, montant_remise, montant_net,
             montant_cout, montant_marge)
        SELECT cle_date, cle_produit, cle_client, cle_employe,
               cle_fournisseur, cle_canal, cle_geographie_client,
               commande_id, numero_ligne,
               quantite, prix_unitaire, cout_unitaire, pct_remise,
               montant_brut, montant_remise, montant_net,
               montant_cout, montant_marge
          FROM fact.fait_ventes;

        DECLARE @rows_out BIGINT = @@ROWCOUNT;
        EXEC etl.sp_run_end @run_id, N'SUCCESS', @rows_out, @rows_out;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC etl.sp_run_end @run_id, N'FAIL', NULL, NULL, @err;
        THROW;
    END CATCH
END
GO

-- ----------------------------------------------------------------------------
-- sp_run_complet -- enchaine charger_staging + run_pipeline + pousser_dwh.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('etl.sp_run_complet','P') IS NOT NULL
    DROP PROCEDURE etl.sp_run_complet;
GO

CREATE PROCEDURE etl.sp_run_complet
AS
BEGIN
    SET NOCOUNT ON;
    PRINT '=== ETL run start ===';
    EXEC etl.sp_charger_staging;
    EXEC etl.sp_run_pipeline;       -- procedure deja creee dans le script 09
    EXEC etl.sp_pousser_dwh;
    PRINT '=== ETL run OK ===';
END
GO

PRINT '[11] OK -- orchestrateur T-SQL pret. Pour executer le pipeline complet :';
PRINT '       USE OrionETL;';
PRINT '       EXEC etl.sp_run_complet;';
GO
