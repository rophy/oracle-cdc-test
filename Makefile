.DEFAULT_GOAL := help
.PHONY: up up-olr up-full down clean help

up: ## Start base stack (Oracle + monitoring)
	docker compose up -d

up-olr: ## Start with OLR direct to file
	docker compose --profile=olr-only up -d

up-full: ## Start full pipeline (OLR → Debezium → Kafka)
	docker compose --profile=full up -d

down: ## Stop all containers (preserves volumes)
	docker compose --profile=olr-only --profile=full down

clean: ## Clean output files and remove everything including volumes
	docker compose --profile=clean run --rm clean
	docker compose --profile=olr-only --profile=full down -v

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'
