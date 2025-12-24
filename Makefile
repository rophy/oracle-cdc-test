.DEFAULT_GOAL := help
.PHONY: up up-olr up-full down clean run-bench report help check-mode

# Check DEPLOY_MODE is set
check-mode:
ifndef DEPLOY_MODE
	$(error DEPLOY_MODE is not set. Use: export DEPLOY_MODE=docker or export DEPLOY_MODE=k8s)
endif
ifneq ($(DEPLOY_MODE),docker)
ifneq ($(DEPLOY_MODE),k8s)
	$(error DEPLOY_MODE must be 'docker' or 'k8s', got '$(DEPLOY_MODE)')
endif
endif

up: check-mode ## Start base stack (Oracle + monitoring)
	./scripts/$(DEPLOY_MODE)/up.sh

up-olr: check-mode ## Start with OLR direct to file
	./scripts/$(DEPLOY_MODE)/up-olr.sh

up-full: check-mode ## Start full pipeline (OLR → Debezium → Kafka)
	./scripts/$(DEPLOY_MODE)/up-full.sh

down: check-mode ## Stop all containers/pods (preserves volumes/PVCs)
	./scripts/$(DEPLOY_MODE)/down.sh

clean: check-mode ## Clean output files and remove everything including volumes/PVCs
	./scripts/$(DEPLOY_MODE)/clean.sh

run-bench: check-mode ## Run HammerDB benchmark with timestamp tracking
	./scripts/$(DEPLOY_MODE)/run-bench.sh

report: check-mode ## Generate performance report from last benchmark run
	./scripts/$(DEPLOY_MODE)/report.sh

help: ## Show this help
	@echo "Usage: DEPLOY_MODE=<docker|k8s> make <target>"
	@echo ""
	@echo "Environment variables:"
	@echo "  DEPLOY_MODE    Required. Set to 'docker' or 'k8s'"
	@echo "  K8S_NAMESPACE  Kubernetes namespace (default: oracle-cdc)"
	@echo "  HELM_RELEASE   Helm release name (default: oracle-cdc)"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
