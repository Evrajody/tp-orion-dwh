# Captures d'écran à insérer (placeholders du rapport)

Ce dossier doit contenir les captures suivantes (PNG, ~1500 px de large
recommandé). Tant qu'un fichier est absent, le rapport affiche un cadre
gris « Capture d'écran à insérer » à sa place — la compilation
n'est jamais cassée par une absence.

| Fichier                            | Section / contexte                                                        |
|------------------------------------|---------------------------------------------------------------------------|
| `transition-adminer-oltp-vs-etl.png` | §3 Transition OLTP→DWH — vue côte à côte schéma `ops` vs `OrionETL` dans Adminer |
| `docker-compose-ps.png`              | §5 Docker — sortie de `docker compose ps` (5 services Up/healthy)                 |
| `docker-startup.png`                 | §5 Docker — `docker compose up -d --build` puis `logs -f orchestrator`            |
| `adminer-login.png`                  | §5 Docker — écran de connexion Adminer avec sélecteur de cible                    |
| `ssms-objects.png` (ou `adminer-orionetl.png`) | §7 ETL — arborescence `OrionETL` (staging / etl / dim / fact) |
| `ssms-sp-execute.png`                | §7 ETL — exécution manuelle d'`etl.sp_run_pipeline` (sortie + durée)              |
| `orchestrator-logs.png`              | §7 ETL — logs Docker de l'orchestrateur sur un run complet                        |
| `ssms-run-log.png`                   | §7 ETL — `SELECT * FROM etl.run_log` montrant les derniers runs                   |
| `adminer-dwh-fact.png`               | Annexe B — aperçu d'une ligne de `dw.fait_ventes` dans Adminer (cible Orion DWH)  |
| `queries-result.png`                 | Annexe B — résultat d'une requête analytique (Q1 par exemple)                     |

Pour ajouter une capture :

```fish
# placer le PNG ici puis recompiler
cp ~/Téléchargements/Capture123.png screenshots/ssms-objects.png
cd /home/evrajodygildas/dev-laboratory/tp-ed-eneam/tp1-orion/doc/rapport
./build.sh
```

La macro `\screenshot{fichier.png}{Légende}` détecte automatiquement la
présence du fichier et l'inclut s'il existe, sinon affiche le placeholder.
