.DEFAULT_GOAL := help
.PHONY: up down clean build run-bench report help check-mode check-profile

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

# Check PROFILE is set
check-profile:
ifndef PROFILE
	$(error PROFILE is not set. Use: export PROFILE=full or export PROFILE=olr-only)
endif
ifneq ($(PROFILE),full)
ifneq ($(PROFILE),olr-only)
	$(error PROFILE must be 'full' or 'olr-only', got '$(PROFILE)')
endif
endif

up: check-mode check-profile ## Start stack based on PROFILE
	./scripts/$(DEPLOY_MODE)/up.sh

down: check-mode ## Stop all containers/pods (preserves volumes/PVCs)
	./scripts/$(DEPLOY_MODE)/down.sh

clean: check-mode ## Clean output files and remove everything including volumes/PVCs
	./scripts/$(DEPLOY_MODE)/clean.sh

build: check-mode check-profile ## Build TPCC schema and configure CDC (waits for Oracle)
	./scripts/$(DEPLOY_MODE)/build.sh

run-bench: check-mode ## Run HammerDB benchmark with timestamp tracking
	./scripts/$(DEPLOY_MODE)/run-bench.sh

report: check-mode ## Generate performance report from last benchmark run
	./scripts/$(DEPLOY_MODE)/report.sh

help: ## Show this help
	@echo "Usage: DEPLOY_MODE=<docker|k8s> PROFILE=<full|olr-only> make <target>"
	@echo ""
	@echo "Environment variables:"
	@echo "  DEPLOY_MODE    Required. 'docker' or 'k8s'"
	@echo "  PROFILE        Required for up/build. 'full' or 'olr-only'"
	@echo "  K8S_NAMESPACE  Kubernetes namespace (default: oracle-cdc)"
	@echo "  HELM_RELEASE   Helm release name (default: oracle-cdc)"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
