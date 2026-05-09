# =============================================================================
#  Orion — pilote de la stack docker compose
#    services : postgres-oltp, postgres-dwh, mssql-etl, orchestrator,
#               data-gen (profil "seed"), adminer-{oltp,dwh,mssql}
# =============================================================================

COMPOSE ?= docker compose

.DEFAULT_GOAL := help
.PHONY: help up down clean nuke build rebuild seed fresh ps logs restart-orchestrator

help:  ## affiche les cibles disponibles
	@awk 'BEGIN{FS=":.*?## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# --- cycle de vie -----------------------------------------------------------

up:  ## démarre la stack en arrière-plan (sans rebuild)
	$(COMPOSE) up -d

down:  ## arrête la stack (volumes conservés)
	$(COMPOSE) down

clean:  ## arrête tout + supprime volumes & orphelins (reset complet)
	$(COMPOSE) down -v --remove-orphans

nuke:  ## clean + supprime aussi les images locales du projet
	$(COMPOSE) down -v --rmi local --remove-orphans

build:  ## construit les images (cache OK)
	$(COMPOSE) build

rebuild:  ## reconstruit les images sans cache
	$(COMPOSE) build --no-cache

seed:  ## peuple Postgres OLTP via data-gen (profil "seed")
	$(COMPOSE) --profile seed run --rm data-gen

# --- allumage complet -------------------------------------------------------

fresh: clean  ## suppression totale + rebuild + up + seed (allumage propre)
	$(COMPOSE) up -d --build
	$(COMPOSE) --profile seed run --rm data-gen
	@echo ""
	@echo "stack prête — vérifier avec : make ps"

# --- aides ------------------------------------------------------------------

ps:  ## liste les services et leur état
	$(COMPOSE) ps

logs:  ## suit les logs (ex : make logs S=mssql-etl)
	$(COMPOSE) logs -f $(S)

restart-orchestrator:  ## relance le service orchestrateur
	$(COMPOSE) restart orchestrator
