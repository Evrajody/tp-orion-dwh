================================================================================
  ORION  --  MIGRATION VERS SQL SERVER / WINDOWS
  Scripts T-SQL numerotes a executer dans l'ordre, dans SSMS.
================================================================================

OBJECTIF
--------
Reproduire sur une instance SQL Server unique (Windows) la stack Docker
Postgres+SQL Server du projet Orion. Le resultat final : 3 bases sur la meme
instance (OrionOLTP, OrionETL, OrionDWH) et un pipeline ETL fonctionnel.

PRE-REQUIS
----------
1. SQL Server 2022 ou 2025 Developer Edition installe avec :
     - Database Engine Services
     - Integration Services (necessaire pour le catalogue SSISDB plus tard)
     - SQL Server Agent en demarrage Automatic
2. SSMS 20.x ou 21.x installe.
3. Authentification Windows ou compte SQL avec privileges sysadmin sur
   l'instance.
4. Si SSMS 21 + SQL Server 2022 : creer le lien symbolique
     mklink /D "C:\Program Files\Microsoft SQL Server\170" ^
               "C:\Program Files\Microsoft SQL Server\160"
   (terminal Administrateur) avant de creer SSISDB. Cf. guide
   migration-windows-sqlserver.pdf section 2.2.4.

ARCHITECTURE CIBLE
------------------
   +---------------+     +-------------------+     +---------------+
   |   OrionOLTP   |     |     OrionETL      |     |   OrionDWH    |
   |    (bronze)   |     |     (silver)      |     |     (gold)    |
   |   schema ops  | --> | schemas etl,      | --> |  schema dw    |
   |               |     | staging,dim,fact  |     |               |
   +---------------+     +-------------------+     +---------------+
   donnees brutes        zone de transformation     modele etoile
   3NF                   procedures stockees        lecture seule

ORDRE D'EXECUTION DES SCRIPTS
=============================

Etape  Fichier                          Cible (USE ...)   But
-----  -------------------------------  ----------------  -----------------------
  01   01_create_databases.sql          master            Cree les 3 bases (collation)
  02   02_oltp_schema.sql               OrionOLTP         Schema 3NF dans schema ops
  03   03_oltp_static_data.sql          OrionOLTP         Donnees de reference
                                                           (continents, pays, canaux,
                                                            org RH, hierarchie produits,
                                                            groupes clients)
  04   04_etl_meta_tables.sql           OrionETL          etl.run_log, etl.watermark,
                                                           sp_run_start, sp_run_end
  05   05_etl_staging.sql               OrionETL          7 tables staging.*
  06   06_etl_dim_tables.sql            OrionETL          dim.* + fact.fait_ventes
  07   07_etl_sp_dim_simple.sql         OrionETL          5 procedures SCD1
                                                           (dim_date, dim_canal,
                                                           dim_geographie,
                                                           dim_fournisseur, dim_produit)
  08   08_etl_sp_dim_scd2.sql           OrionETL          2 procedures SCD2
                                                           (dim_client, dim_employe)
                                                           AVEC les 5 colonnes contrat
  09   09_etl_sp_fact.sql               OrionETL          sp_load_fait_ventes +
                                                           sp_run_pipeline
  10   10_dwh_schema.sql                OrionDWH          Schema en etoile (dw.*)
  11   11_orchestrator_tsql.sql         OrionETL          sp_charger_staging,
                                                           sp_pousser_dwh,
                                                           sp_run_complet
                                                           (= equivalent T-SQL de
                                                           orchestrate.py pour la
                                                           voie A "tout T-SQL")
  99   99_verify.sql                    multiple          Requetes de verification

PROCEDURE PAS-A-PAS
===================

Pour chaque script :
  a) Ouvrir le fichier dans SSMS (File > Open > File ou Ctrl+O).
  b) Verifier la base courante en haut a gauche de la fenetre Query
     (combobox "Available databases"). Cliquer pour la changer si besoin.
     - Pour 01     -> master
     - Pour 02-03  -> OrionOLTP
     - Pour 04-09  -> OrionETL
     - Pour 10     -> OrionDWH
     - Pour 11     -> OrionETL
     NB: chaque fichier commence par un "USE <BASE>;" qui fait basculer
     automatiquement, donc tu peux aussi laisser SSMS sur master.
  c) Executer avec F5.
  d) Verifier dans le panneau "Messages" qu'aucune erreur rouge n'apparait.
  e) Passer au script suivant.

Duree typique pour les 11 scripts : 5 a 10 minutes en SSMS.

ETAPE FACULTATIVE -- ALIMENTATION DES DONNEES
==============================================
Apres execution des scripts 01 a 11, OrionOLTP contient :
  - Les donnees de reference (continents, pays, canaux, org RH,
    hierarchie produits, groupes clients).
  - AUCUNE donnee operationnelle (clients, produits, commandes...).

Pour peupler avec des donnees fictives realistes (~ 90 000 clients,
980 000 commandes, etc.), 3 options :

OPTION 1 (recommandee) -- reutiliser le data-gen Python existant.
   Sur Windows :
     pip install pyodbc faker
     # adapter data-gen/generate.py pour pointer vers SQL Server :
     # connexion via pyodbc + executemany(...)
   Cf. doc/rapport/migration-windows-sqlserver.pdf section 12.

OPTION 2 -- script T-SQL avec WHILE et RAND() (fastidieux pour 980k commandes).

OPTION 3 -- package SSIS Orion_Seed.dtsx avec Script Component + lib Bogus.
   Detaille dans le guide de migration.

LANCEMENT DE L'ETL
==================

VOIE A (tout T-SQL, plus simple a tester) :
   USE OrionETL;
   EXEC etl.sp_run_complet;
Cela appelle sp_charger_staging, sp_run_pipeline, sp_pousser_dwh dans
l'ordre. Ce code est fourni dans le script 11.

VOIE B (SSIS, livrable visuel) :
   Suivre le guide migration-windows-sqlserver.pdf, sections 6 a 14.
   Les Connection Managers SSIS pointent sur les memes 3 bases creees
   par les scripts ci-dessus. Le projet SSIS execute :
     1. Charge le staging via Data Flow Tasks (lecture OrionOLTP)
     2. Appelle EXEC etl.sp_run_pipeline (deja cree par les scripts 07-09)
     3. Pousse vers OrionDWH via Data Flow Tasks
   La voie B reutilise donc tout le code T-SQL deja installe par les
   scripts 04-10.

VERIFICATION FINALE
===================

Apres un run ETL complet, executer 99_verify.sql qui doit retourner :
  - SELECT COUNT(*) FROM OrionDWH.dw.fait_ventes;        -- > 0
  - SELECT COUNT(*) FROM OrionDWH.dw.dim_client;         -- > 0
  - SELECT COUNT(*) FROM OrionDWH.dw.dim_employe;        -- > 0
  - Les 5 colonnes contrat sont bien renseignees dans dim_employe.
  - SELECT TOP 10 * FROM OrionETL.etl.run_log ORDER BY run_id DESC;
       -- doit afficher des lignes avec status='SUCCESS'.

REINITIALISATION
================

Pour repartir a zero (perte des donnees garantie) :
   USE master;
   ALTER DATABASE OrionOLTP SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
   DROP DATABASE OrionOLTP;
   ALTER DATABASE OrionETL  SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
   DROP DATABASE OrionETL;
   ALTER DATABASE OrionDWH  SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
   DROP DATABASE OrionDWH;
Puis reexecuter les scripts 01 a 11.

DEPANNAGE
=========

Erreur                                           Solution
-----------------------------------------------  -------------------------------
"Cannot open database OrionETL"                  Le script 01 n'a pas ete
                                                 execute ou a echoue.
"Invalid object name 'staging.canal'"            Le script 05 n'a pas ete
                                                 execute. Verifier l'ordre.
"Cannot insert duplicate key" sur IDENTITY       Mode fast-load SSIS active
                                                 "Keep identity = true" par
                                                 erreur. Le decocher.
"Cannot resolve collation conflict"              Une base a ete creee sans
                                                 specifier French_CI_AS.
                                                 Recreer toutes les bases avec
                                                 la meme collation.
SSISDBBackup.bak introuvable                     Cf. guide migration-windows-
                                                 sqlserver.pdf section 2.2.4.

CONTACT / DOCUMENTATION ASSOCIEE
================================
- Architecture detaillee :       doc/MODELISATION.md
- Modelisation revue :           doc/rapport/modelisation-revue.pdf
- Guide setup complet (Docker) : doc/rapport/setup.pdf
- Guide SSIS Windows complet :   doc/rapport/migration-windows-sqlserver.pdf
- UML complet :                  doc/rapport/uml-complet.pdf
- Rapport principal :            doc/rapport/rapport.pdf

================================================================================
  Fin du README. Bonne migration.
================================================================================
