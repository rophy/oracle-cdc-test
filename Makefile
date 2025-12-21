.PHONY: up down clean help

up: ## Start the stack
	docker compose up -d

down: ## Stop containers (preserves volumes)
	docker compose down

clean: ## Clean output files and remove everything including volumes
	docker compose --profile=clean run --rm clean
	docker compose down -v

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-10s %s\n", $$1, $$2}'
