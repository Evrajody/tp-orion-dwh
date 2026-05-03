-- ============================================================================
--  07 — Procédure stockée : table de faits fait_ventes (incrémentale).
--  Lit les nouvelles lignes depuis staging.lignes_commande, résout les
--  surrogate keys par lookup sur dim.* et calcule les mesures dérivées.
-- ============================================================================
USE OrionETL;
GO

IF OBJECT_ID(N'etl.sp_load_fait_ventes','P') IS NOT NULL DROP PROCEDURE etl.sp_load_fait_ventes;
GO
CREATE PROCEDURE etl.sp_load_fait_ventes
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id BIGINT;
    EXEC etl.sp_run_start @job_name = N'fait_ventes', @run_id = @run_id OUTPUT;

    BEGIN TRY
        DECLARE @rows_in  BIGINT = (SELECT COUNT(*) FROM staging.lignes_commande);
        DECLARE @rows_out BIGINT;

        -- Suppression des collisions (re-run d'un même commande_id, numero_ligne)
        DELETE f
          FROM fact.fait_ventes f
          JOIN staging.lignes_commande s
            ON s.commande_id  = f.commande_id
           AND s.numero_ligne = f.numero_ligne;

        INSERT fact.fait_ventes
            (cle_date, cle_produit, cle_client, cle_employe, cle_fournisseur,
             cle_canal, cle_geographie_client,
             commande_id, numero_ligne,
             quantite, prix_unitaire, cout_unitaire, pct_remise,
             montant_brut, montant_remise, montant_net,
             montant_cout, montant_marge)
        SELECT
            CONVERT(INT, FORMAT(s.date_commande, 'yyyyMMdd')),
            dp.cle_produit,
            dc.cle_client,
            de.cle_employe,
            df.cle_fournisseur,
            dch.cle_canal,
            dg.cle_geographie,
            s.commande_id, s.numero_ligne,
            s.quantite, s.prix_unitaire, s.cout_unitaire, s.pct_remise,
            -- mesures dérivées
            s.quantite * s.prix_unitaire                                 AS montant_brut,
            s.quantite * s.prix_unitaire * s.pct_remise                  AS montant_remise,
            s.quantite * s.prix_unitaire * (1 - s.pct_remise)            AS montant_net,
            s.quantite * s.cout_unitaire                                 AS montant_cout,
            s.quantite * s.prix_unitaire * (1 - s.pct_remise)
              - s.quantite * s.cout_unitaire                             AS montant_marge
        FROM staging.lignes_commande s
        JOIN dim.dim_produit     dp ON dp.produit_id    = s.produit_id
        -- la version SCD2 « courante » au moment du chargement
        JOIN dim.dim_client      dc ON dc.client_id     = s.client_id    AND dc.est_courant = 1
        JOIN dim.dim_employe     de ON de.employe_id    = s.employe_id   AND de.est_courant = 1
        JOIN dim.dim_fournisseur df ON df.fournisseur_id= s.fournisseur_id
        JOIN dim.dim_canal       dch ON dch.canal_id    = s.canal_id
        JOIN dim.dim_geographie  dg  ON dg.ville_id     = s.cli_ville_id;

        SET @rows_out = @@ROWCOUNT;

        -- Mise à jour du watermark (la plus grande date_commande traitée)
        DECLARE @max_dt DATETIME2(3) =
            (SELECT CONVERT(DATETIME2(3), MAX(date_commande)) FROM staging.lignes_commande);

        IF @max_dt IS NOT NULL
        BEGIN
            MERGE etl.watermark AS t
            USING (SELECT N'fait_ventes' AS job_name, @max_dt AS last_value) AS s
               ON t.job_name = s.job_name
            WHEN MATCHED     THEN UPDATE SET last_value = s.last_value,
                                              updated_at = SYSUTCDATETIME()
            WHEN NOT MATCHED THEN INSERT(job_name, last_value)
                                  VALUES (s.job_name, s.last_value);
        END

        EXEC etl.sp_run_end @run_id, N'SUCCESS', @rows_in, @rows_out;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC etl.sp_run_end @run_id, N'FAIL', NULL, NULL, @err;
        THROW;
    END CATCH
END
GO

-- ---------------------------------------------------------------------------
-- Procédure « tout en un » : exécute la suite complète après chargement
-- des tables de staging par l'orchestrateur.
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'etl.sp_run_pipeline','P') IS NOT NULL DROP PROCEDURE etl.sp_run_pipeline;
GO
CREATE PROCEDURE etl.sp_run_pipeline
AS
BEGIN
    SET NOCOUNT ON;
    EXEC etl.sp_load_dim_date;
    EXEC etl.sp_load_dim_canal;
    EXEC etl.sp_load_dim_geographie;
    EXEC etl.sp_load_dim_fournisseur;
    EXEC etl.sp_load_dim_produit;
    EXEC etl.sp_load_dim_client;
    EXEC etl.sp_load_dim_employe;
    EXEC etl.sp_load_fait_ventes;
END
GO

PRINT '[07] sp_load_fait_ventes + sp_run_pipeline OK.';
GO
