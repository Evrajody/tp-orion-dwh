#!/usr/bin/env bash
# Démarre SQL Server, attend qu'il accepte les connexions, puis applique
# (idempotent) les scripts d'initialisation du schéma ETL.
set -euo pipefail

SQLCMD="/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P ${MSSQL_SA_PASSWORD} -No"

# Lancement du serveur SQL en arrière-plan
/opt/mssql/bin/sqlservr &
SQL_PID=$!

# Attente que SQL Server réponde
echo "[mssql-etl] attente de la disponibilité de SQL Server..."
for i in $(seq 1 60); do
  if $SQLCMD -Q "SELECT 1" >/dev/null 2>&1; then
    echo "[mssql-etl] SQL Server prêt."
    break
  fi
  sleep 2
done

# Application des scripts d'init (créés via volume monté en lecture)
INIT_DIR="/usr/src/mssql-etl/init"
if [ -d "$INIT_DIR" ]; then
  for f in $(ls "$INIT_DIR"/*.sql 2>/dev/null | sort); do
    echo "[mssql-etl] exécution $f"
    $SQLCMD -i "$f" -b || {
      echo "[mssql-etl] échec sur $f" >&2
      exit 1
    }
  done
fi

echo "[mssql-etl] initialisation terminée — moteur ETL en service."

# Reste attaché au process SQL Server
wait $SQL_PID
