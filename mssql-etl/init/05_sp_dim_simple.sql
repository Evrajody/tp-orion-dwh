-- ============================================================================
--  05 — Procédures stockées : dimensions SCD1 (full reload).
--  Pattern : TRUNCATE + INSERT depuis staging.* préalablement chargée
--  par l'orchestrateur depuis Postgres OLTP.
-- ============================================================================
USE OrionETL;
GO

-- ---------------------------------------------------------------------------
-- dim_date — bootstrap statique (idempotent : ne fait rien si déjà rempli)
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'etl.sp_load_dim_date','P') IS NOT NULL DROP PROCEDURE etl.sp_load_dim_date;
GO
CREATE PROCEDURE etl.sp_load_dim_date
    @date_debut DATE = '1997-01-01',
    @date_fin   DATE = '2003-12-31'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id BIGINT;
    EXEC etl.sp_run_start @job_name = N'dim_date', @run_id = @run_id OUTPUT;

    BEGIN TRY
        IF EXISTS (SELECT 1 FROM dim.dim_date)
        BEGIN
            EXEC etl.sp_run_end @run_id = @run_id, @status = N'SUCCESS',
                                @rows_in = 0, @rows_out = 0;
            RETURN;
        END

        ;WITH d AS (
            SELECT @date_debut AS dt
            UNION ALL
            SELECT DATEADD(DAY, 1, dt) FROM d WHERE dt < @date_fin
        )
        INSERT dim.dim_date
            (cle_date, date_complete, jour_du_mois, numero_mois, nom_mois,
             numero_trimestre, annee, jour_de_semaine, nom_jour,
             semaine_annee, est_weekend, saison)
        SELECT
            CONVERT(INT, FORMAT(dt, 'yyyyMMdd')),
            dt,
            DAY(dt),
            MONTH(dt),
            DATENAME(MONTH, dt),
            DATEPART(QUARTER, dt),
            YEAR(dt),
            ((DATEPART(WEEKDAY, dt) + @@DATEFIRST - 2) % 7) + 1,
            DATENAME(WEEKDAY, dt),
            DATEPART(ISO_WEEK, dt),
            CASE WHEN DATENAME(WEEKDAY, dt) IN ('Saturday','Sunday',
                                                'samedi','dimanche')
                 THEN 1 ELSE 0 END,
            CASE
                WHEN MONTH(dt) IN (12,1,2)  THEN N'Hiver'
                WHEN MONTH(dt) IN (3,4,5)   THEN N'Printemps'
                WHEN MONTH(dt) IN (6,7,8)   THEN N'Été'
                ELSE N'Automne'
            END
        FROM d OPTION (MAXRECURSION 0);

        DECLARE @cnt BIGINT = (SELECT COUNT(*) FROM dim.dim_date);
        EXEC etl.sp_run_end @run_id = @run_id, @status = N'SUCCESS',
                            @rows_in = @cnt, @rows_out = @cnt;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC etl.sp_run_end @run_id = @run_id, @status = N'FAIL', @error = @err;
        THROW;
    END CATCH
END
GO

-- ---------------------------------------------------------------------------
-- dim_canal
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'etl.sp_load_dim_canal','P') IS NOT NULL DROP PROCEDURE etl.sp_load_dim_canal;
GO
CREATE PROCEDURE etl.sp_load_dim_canal
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id BIGINT;
    EXEC etl.sp_run_start @job_name = N'dim_canal', @run_id = @run_id OUTPUT;

    BEGIN TRY
        TRUNCATE TABLE dim.dim_canal;
        INSERT dim.dim_canal(canal_id, code_canal, nom_canal)
        SELECT canal_id, code_canal, nom_canal FROM staging.canal;

        DECLARE @cnt BIGINT = @@ROWCOUNT;
        EXEC etl.sp_run_end @run_id, N'SUCCESS', @cnt, @cnt;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC etl.sp_run_end @run_id, N'FAIL', NULL, NULL, @err;
        THROW;
    END CATCH
END
GO

-- ---------------------------------------------------------------------------
-- dim_geographie
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'etl.sp_load_dim_geographie','P') IS NOT NULL DROP PROCEDURE etl.sp_load_dim_geographie;
GO
CREATE PROCEDURE etl.sp_load_dim_geographie
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id BIGINT;
    EXEC etl.sp_run_start @job_name = N'dim_geographie', @run_id = @run_id OUTPUT;

    BEGIN TRY
        TRUNCATE TABLE dim.dim_geographie;
        INSERT dim.dim_geographie
            (ville_id, nom_ville, nom_region, code_pays, nom_pays,
             nom_continent, code_postal)
        SELECT ville_id, nom_ville, nom_region, code_pays, nom_pays,
               nom_continent, code_postal
        FROM staging.geographie_full;

        DECLARE @cnt BIGINT = @@ROWCOUNT;
        EXEC etl.sp_run_end @run_id, N'SUCCESS', @cnt, @cnt;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC etl.sp_run_end @run_id, N'FAIL', NULL, NULL, @err;
        THROW;
    END CATCH
END
GO

-- ---------------------------------------------------------------------------
-- dim_fournisseur
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'etl.sp_load_dim_fournisseur','P') IS NOT NULL DROP PROCEDURE etl.sp_load_dim_fournisseur;
GO
CREATE PROCEDURE etl.sp_load_dim_fournisseur
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id BIGINT;
    EXEC etl.sp_run_start @job_name = N'dim_fournisseur', @run_id = @run_id OUTPUT;

    BEGIN TRY
        TRUNCATE TABLE dim.dim_fournisseur;
        INSERT dim.dim_fournisseur
            (fournisseur_id, nom_fournisseur, nom_pays, nom_continent)
        SELECT fournisseur_id, nom_fournisseur, nom_pays, nom_continent
        FROM staging.fournisseur_full;

        DECLARE @cnt BIGINT = @@ROWCOUNT;
        EXEC etl.sp_run_end @run_id, N'SUCCESS', @cnt, @cnt;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC etl.sp_run_end @run_id, N'FAIL', NULL, NULL, @err;
        THROW;
    END CATCH
END
GO

-- ---------------------------------------------------------------------------
-- dim_produit (SCD1 — full reload)
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'etl.sp_load_dim_produit','P') IS NOT NULL DROP PROCEDURE etl.sp_load_dim_produit;
GO
CREATE PROCEDURE etl.sp_load_dim_produit
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id BIGINT;
    EXEC etl.sp_run_start @job_name = N'dim_produit', @run_id = @run_id OUTPUT;

    BEGIN TRY
        TRUNCATE TABLE dim.dim_produit;
        INSERT dim.dim_produit
            (produit_id, nom_produit, nom_groupe_produit,
             nom_categorie_produit, nom_ligne_produit, fournisseur_id_naturel,
             nom_fournisseur, actif)
        SELECT produit_id, nom_produit, nom_groupe_produit,
               nom_categorie_produit, nom_ligne_produit, fournisseur_id_naturel,
               nom_fournisseur, actif
        FROM staging.produit_full;

        DECLARE @cnt BIGINT = @@ROWCOUNT;
        EXEC etl.sp_run_end @run_id, N'SUCCESS', @cnt, @cnt;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC etl.sp_run_end @run_id, N'FAIL', NULL, NULL, @err;
        THROW;
    END CATCH
END
GO

PRINT '[05] Procédures dimensions SCD1 (FR) prêtes.';
GO
