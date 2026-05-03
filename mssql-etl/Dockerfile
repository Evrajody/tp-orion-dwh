# =============================================================================
#  SQL Server 2022 — moteur ETL pour Orion
#  Contient les procédures stockées T-SQL qui transforment les données OLTP
#  en données dimensionnelles. Les transferts Postgres <-> SQL Server sont
#  effectués par un service orchestrateur séparé (cf. orchestrator/).
# =============================================================================
FROM mcr.microsoft.com/mssql/server:2022-latest

USER root

# unixODBC + driver ODBC PostgreSQL : nécessaire si l'on souhaite plus tard
# tester un Linked Server vers Postgres directement (option « tout SQL Server »
# documentée dans le rapport). Le pipeline par défaut passe par
# l'orchestrateur.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        unixodbc unixodbc-dev odbc-postgresql && \
    rm -rf /var/lib/apt/lists/*

COPY scripts/init-db.sh    /usr/src/mssql-etl/init-db.sh
COPY scripts/entrypoint.sh /usr/src/mssql-etl/entrypoint.sh
COPY init                  /usr/src/mssql-etl/init

# Garde-fou : si les fichiers ont été copiés depuis un poste Windows
# (CRLF), on supprime les \r qui font échouer le shebang « bash\r » et
# qui peuvent perturber la lecture des scripts T-SQL.
RUN sed -i 's/\r$//' /usr/src/mssql-etl/*.sh \
                     /usr/src/mssql-etl/init/*.sql && \
    chmod +x /usr/src/mssql-etl/*.sh

USER mssql

ENV ACCEPT_EULA=Y \
    MSSQL_PID=Developer

ENTRYPOINT ["/usr/src/mssql-etl/entrypoint.sh"]
CMD ["/opt/mssql/bin/sqlservr"]
