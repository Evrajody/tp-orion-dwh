#!/usr/bin/env bash
# Démarre SQL Server, attend qu'il accepte les connexions, puis applique
# (idempotent) les scripts d'initialisation du schéma ETL.
set -euo pipefail

# -f 65001 : force la lecture UTF-8 des fichiers .sql (sinon les accents
#            français des PRINT cassent le parser T-SQL).
# -b       : sortie en erreur si une commande SQL échoue.
# -No      : ignore le « No host name was specified » sur cluster local.
SQLCMD="/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P ${MSSQL_SA_PASSWORD} -No -f 65001"

# Lancement du serveur SQL en arrière-plan
/opt/mssql/bin/sqlservr &
SQL_PID=$!

# Attente que SQL Server réponde
echo "[mssql-etl] attente de la disponibilité de SQL Server..."
ready=0
for i in $(seq 1 60); do
  if $SQLCMD -Q "SELECT 1" >/dev/null 2>&1; then
    echo "[mssql-etl] SQL Server prêt (après $((i*2))s)."
    ready=1
    break
  fi
  sleep 2
done

if [ $ready -eq 0 ]; then
  echo "[mssql-etl] SQL Server n'a pas répondu après 120s." >&2
  exit 1
fi

# Application des scripts d'init (montés en lecture)
INIT_DIR="/usr/src/mssql-etl/init"
if [ -d "$INIT_DIR" ]; then
  for f in $(ls "$INIT_DIR"/*.sql 2>/dev/null | sort); do
    echo "------------------------------------------------------------"
    echo "[mssql-etl] exécution $f"
    if ! $SQLCMD -i "$f" -b; then
      echo "[mssql-etl] ÉCHEC sur $f" >&2
      echo "[mssql-etl] (premières lignes du script qui a échoué :)" >&2
      head -20 "$f" >&2
      exit 1
    fi
  done
fi

echo "============================================================"
echo "[mssql-etl] initialisation terminée — moteur ETL en service."
echo "============================================================"

# Reste attaché au process SQL Server
wait $SQL_PID
