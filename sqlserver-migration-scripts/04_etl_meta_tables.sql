-- ============================================================================
--  02 — Méta ETL : journal d'exécution + watermarks incrémentaux
-- ============================================================================
USE OrionETL;
GO

-- Journal d'exécution
IF OBJECT_ID(N'etl.run_log','U') IS NULL
CREATE TABLE etl.run_log (
    run_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    job_name    NVARCHAR(80)  NOT NULL,
    started_at  DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    ended_at    DATETIME2(3)  NULL,
    status      NVARCHAR(16)  NOT NULL DEFAULT 'RUNNING', -- RUNNING/SUCCESS/FAIL
    rows_in     BIGINT        NULL,
    rows_out    BIGINT        NULL,
    error_msg   NVARCHAR(MAX) NULL
);
GO

-- Watermark : pour le chargement incrémental de fact_sales notamment
IF OBJECT_ID(N'etl.watermark','U') IS NULL
CREATE TABLE etl.watermark (
    job_name    NVARCHAR(80) PRIMARY KEY,
    last_value  DATETIME2(3) NOT NULL,
    updated_at  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- Helpers : ouvrir / fermer un run
IF OBJECT_ID(N'etl.sp_run_start','P') IS NOT NULL DROP PROCEDURE etl.sp_run_start;
GO
CREATE PROCEDURE etl.sp_run_start
    @job_name NVARCHAR(80),
    @run_id   BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT etl.run_log(job_name) VALUES(@job_name);
    SET @run_id = SCOPE_IDENTITY();
END
GO

IF OBJECT_ID(N'etl.sp_run_end','P') IS NOT NULL DROP PROCEDURE etl.sp_run_end;
GO
CREATE PROCEDURE etl.sp_run_end
    @run_id   BIGINT,
    @status   NVARCHAR(16),
    @rows_in  BIGINT       = NULL,
    @rows_out BIGINT       = NULL,
    @error    NVARCHAR(MAX)= NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE etl.run_log
       SET ended_at  = SYSUTCDATETIME(),
           status    = @status,
           rows_in   = @rows_in,
           rows_out  = @rows_out,
           error_msg = @error
     WHERE run_id    = @run_id;
END
GO

PRINT '[02] run_log + watermark + helpers OK.';
GO
