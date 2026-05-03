-- ============================================================================
--  06 — Procédures stockées SCD2 : dim_client + dim_employe
--  Pattern : MERGE manuel via row_hash
--    1) calcul hash_ligne (SHA2_256)
--    2) fermer la version courante si le hash change
--    3) insérer la nouvelle version
--    4) insérer les nouvelles clés naturelles
-- ============================================================================
USE OrionETL;
GO

-- helper : tranche d'âge -----------------------------------------------------
IF OBJECT_ID(N'etl.fn_tranche_age','FN') IS NOT NULL DROP FUNCTION etl.fn_tranche_age;
GO
CREATE FUNCTION etl.fn_tranche_age(@naissance DATE) RETURNS NVARCHAR(20)
AS
BEGIN
    IF @naissance IS NULL RETURN N'inconnu';
    DECLARE @age INT = DATEDIFF(YEAR, @naissance, SYSUTCDATETIME());
    RETURN CASE
        WHEN @age <  25 THEN N'<25'
        WHEN @age <  35 THEN N'25-34'
        WHEN @age <  45 THEN N'35-44'
        WHEN @age <  55 THEN N'45-54'
        WHEN @age <  65 THEN N'55-64'
        ELSE                  N'>=65'
    END;
END
GO

-- helper : tranche de salaire ------------------------------------------------
IF OBJECT_ID(N'etl.fn_tranche_salaire','FN') IS NOT NULL DROP FUNCTION etl.fn_tranche_salaire;
GO
CREATE FUNCTION etl.fn_tranche_salaire(@salaire DECIMAL(12,2)) RETURNS NVARCHAR(20)
AS
BEGIN
    RETURN CASE
        WHEN @salaire <  30000 THEN N'<30k'
        WHEN @salaire <  50000 THEN N'30-50k'
        WHEN @salaire <  80000 THEN N'50-80k'
        WHEN @salaire < 120000 THEN N'80-120k'
        ELSE                       N'>=120k'
    END;
END
GO

-- ---------------------------------------------------------------------------
-- dim_client (SCD2)
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'etl.sp_load_dim_client','P') IS NOT NULL DROP PROCEDURE etl.sp_load_dim_client;
GO
CREATE PROCEDURE etl.sp_load_dim_client
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id BIGINT;
    EXEC etl.sp_run_start @job_name = N'dim_client', @run_id = @run_id OUTPUT;

    BEGIN TRY
        DECLARE @ajd DATE = CONVERT(DATE, SYSUTCDATETIME());

        ;WITH src AS (
            SELECT
                client_id, nom_complet, sexe,
                etl.fn_tranche_age(date_naissance)        AS tranche_age,
                groupe_client, a_carte_fidelite,
                nom_ville, nom_pays, nom_continent,
                CONVERT(CHAR(64), HASHBYTES('SHA2_256',
                    CONCAT_WS(N'|',
                        ISNULL(nom_complet,N''),
                        ISNULL(sexe,N''),
                        ISNULL(etl.fn_tranche_age(date_naissance),N''),
                        ISNULL(groupe_client,N''),
                        CONVERT(NVARCHAR, a_carte_fidelite),
                        ISNULL(nom_ville,N''),
                        ISNULL(nom_pays,N''),
                        ISNULL(nom_continent,N''))
                ), 2) AS hash_ligne
            FROM staging.client_full
        )
        UPDATE d
           SET effectif_au = @ajd,
               est_courant = 0
          FROM dim.dim_client d
          JOIN src           s ON s.client_id = d.client_id
         WHERE d.est_courant = 1
           AND d.hash_ligne <> s.hash_ligne;

        ;WITH src AS (
            SELECT
                client_id, nom_complet, sexe,
                etl.fn_tranche_age(date_naissance)        AS tranche_age,
                groupe_client, a_carte_fidelite,
                nom_ville, nom_pays, nom_continent,
                CONVERT(CHAR(64), HASHBYTES('SHA2_256',
                    CONCAT_WS(N'|',
                        ISNULL(nom_complet,N''), ISNULL(sexe,N''),
                        ISNULL(etl.fn_tranche_age(date_naissance),N''),
                        ISNULL(groupe_client,N''),
                        CONVERT(NVARCHAR, a_carte_fidelite),
                        ISNULL(nom_ville,N''),
                        ISNULL(nom_pays,N''),
                        ISNULL(nom_continent,N''))
                ), 2) AS hash_ligne
            FROM staging.client_full
        )
        INSERT dim.dim_client
            (client_id, nom_complet, sexe, tranche_age, groupe_client,
             a_carte_fidelite, nom_ville, nom_pays, nom_continent,
             effectif_du, effectif_au, est_courant, hash_ligne)
        SELECT s.client_id, s.nom_complet, s.sexe, s.tranche_age,
               s.groupe_client, s.a_carte_fidelite,
               s.nom_ville, s.nom_pays, s.nom_continent,
               @ajd, NULL, 1, s.hash_ligne
          FROM src s
          LEFT JOIN dim.dim_client d
            ON d.client_id = s.client_id AND d.est_courant = 1
         WHERE d.cle_client IS NULL OR d.hash_ligne <> s.hash_ligne;

        DECLARE @inserted BIGINT = @@ROWCOUNT;

        EXEC etl.sp_run_end @run_id, N'SUCCESS',
             @rows_in  = (SELECT COUNT(*) FROM staging.client_full),
             @rows_out = @inserted;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC etl.sp_run_end @run_id, N'FAIL', NULL, NULL, @err;
        THROW;
    END CATCH
END
GO

-- ---------------------------------------------------------------------------
-- dim_employe (SCD2)
-- ---------------------------------------------------------------------------
IF OBJECT_ID(N'etl.sp_load_dim_employe','P') IS NOT NULL DROP PROCEDURE etl.sp_load_dim_employe;
GO
CREATE PROCEDURE etl.sp_load_dim_employe
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_id BIGINT;
    EXEC etl.sp_run_start @job_name = N'dim_employe', @run_id = @run_id OUTPUT;

    BEGIN TRY
        DECLARE @ajd DATE = CONVERT(DATE, SYSUTCDATETIME());

        ;WITH src AS (
            SELECT
                employe_id, nom_complet, sexe,
                etl.fn_tranche_age(date_naissance)     AS tranche_age,
                salaire,
                etl.fn_tranche_salaire(salaire)        AS tranche_salaire,
                org_pays, org_compagnie, org_departement,
                org_section, org_groupe, nom_manager,
                date_embauche, date_depart,
                CONVERT(CHAR(64), HASHBYTES('SHA2_256',
                    CONCAT_WS(N'|',
                        nom_complet, sexe,
                        etl.fn_tranche_age(date_naissance),
                        CONVERT(NVARCHAR, salaire),
                        etl.fn_tranche_salaire(salaire),
                        ISNULL(org_pays,N''),    ISNULL(org_compagnie,N''),
                        ISNULL(org_departement,N''), ISNULL(org_section,N''),
                        ISNULL(org_groupe,N''),  ISNULL(nom_manager,N''),
                        CONVERT(NVARCHAR, date_embauche),
                        ISNULL(CONVERT(NVARCHAR, date_depart), N''))
                ), 2) AS hash_ligne
            FROM staging.employe_full
        )
        UPDATE d
           SET effectif_au = @ajd, est_courant = 0
          FROM dim.dim_employe d
          JOIN src             s ON s.employe_id = d.employe_id
         WHERE d.est_courant = 1
           AND d.hash_ligne <> s.hash_ligne;

        ;WITH src AS (
            SELECT
                employe_id, nom_complet, sexe,
                etl.fn_tranche_age(date_naissance)     AS tranche_age,
                salaire,
                etl.fn_tranche_salaire(salaire)        AS tranche_salaire,
                org_pays, org_compagnie, org_departement,
                org_section, org_groupe, nom_manager,
                date_embauche, date_depart,
                CONVERT(CHAR(64), HASHBYTES('SHA2_256',
                    CONCAT_WS(N'|',
                        nom_complet, sexe,
                        etl.fn_tranche_age(date_naissance),
                        CONVERT(NVARCHAR, salaire),
                        etl.fn_tranche_salaire(salaire),
                        ISNULL(org_pays,N''),    ISNULL(org_compagnie,N''),
                        ISNULL(org_departement,N''), ISNULL(org_section,N''),
                        ISNULL(org_groupe,N''),  ISNULL(nom_manager,N''),
                        CONVERT(NVARCHAR, date_embauche),
                        ISNULL(CONVERT(NVARCHAR, date_depart), N''))
                ), 2) AS hash_ligne
            FROM staging.employe_full
        )
        INSERT dim.dim_employe
            (employe_id, nom_complet, sexe, tranche_age, salaire, tranche_salaire,
             org_pays, org_compagnie, org_departement, org_section, org_groupe,
             nom_manager, date_embauche, date_depart,
             effectif_du, effectif_au, est_courant, hash_ligne)
        SELECT s.employe_id, s.nom_complet, s.sexe, s.tranche_age,
               s.salaire, s.tranche_salaire,
               s.org_pays, s.org_compagnie, s.org_departement,
               s.org_section, s.org_groupe, s.nom_manager,
               s.date_embauche, s.date_depart,
               @ajd, NULL, 1, s.hash_ligne
          FROM src s
          LEFT JOIN dim.dim_employe d
            ON d.employe_id = s.employe_id AND d.est_courant = 1
         WHERE d.cle_employe IS NULL OR d.hash_ligne <> s.hash_ligne;

        DECLARE @inserted BIGINT = @@ROWCOUNT;
        EXEC etl.sp_run_end @run_id, N'SUCCESS',
             @rows_in  = (SELECT COUNT(*) FROM staging.employe_full),
             @rows_out = @inserted;
    END TRY
    BEGIN CATCH
        DECLARE @err NVARCHAR(MAX) = ERROR_MESSAGE();
        EXEC etl.sp_run_end @run_id, N'FAIL', NULL, NULL, @err;
        THROW;
    END CATCH
END
GO

PRINT '[06] Procédures SCD2 dim_client + dim_employe (FR) prêtes.';
GO
