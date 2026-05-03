#!/usr/bin/env bash
# Helper : ré-exécute manuellement l'initialisation depuis l'extérieur.
# Usage : docker compose exec mssql-etl /usr/src/mssql-etl/init-db.sh
set -euo pipefail
SQLCMD="/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P ${MSSQL_SA_PASSWORD} -No -f 65001"
for f in $(ls /usr/src/mssql-etl/init/*.sql | sort); do
  echo "[init-db] $f"
  $SQLCMD -i "$f" -b
done
