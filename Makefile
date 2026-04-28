# Makefile for valpay-aws-terraform
.PHONY: help validate plan apply destroy clean fmt lint docs compare create-backend init _init-modules fix-providers


# Default target
help: ## Show this help message
	@echo "Available targets:"
	@echo "  make create-backend <env> - Create backend resources (qa, dev, prod)"
	@echo "  make init <env>           - Initialize Terraform modules (qa, dev, prod)"
	@echo "  make plan <env>           - Plan environment (qa, dev, prod)"
	@echo "  make apply <env>          - Apply environment (qa, dev, prod)"
	@echo "  make fix-providers        - chmod +x Terraform providers (after S3 restore)"
	@echo "  make compare [<source> <destination>] - Compare configurations"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Validation targets
validate: ## Validate all Terraform configurations
	@echo "Validating Terraform configurations..."
	@find modules -name "*.tf" -exec terraform fmt -check {} \;
	@find environments -name "*.hcl" -exec terragrunt hclfmt --terragrunt-check {} \;
	@find modules -name "*.tf" -exec terraform validate {} \;

fmt: ## Format all Terraform and Terragrunt files
	@echo "Formatting Terraform files..."
	@find modules -name "*.tf" -exec terraform fmt {} \;
	@echo "Formatting Terragrunt files..."
	@find environments -name "*.hcl" -exec terragrunt hclfmt {} \;

lint: ## Run linting tools
	@echo "Running tflint..."
	@find modules -name "*.tf" -exec tflint {} \;
	@echo "Running checkov..."
	@checkov -d modules/

# Backend creation and initialization targets
create-backend: ## Create backend resources (usage: make create-backend qa|dev|prod [region])
	@args="$(filter-out $@,$(MAKECMDGOALS))"; \
	if echo "$$args" | grep -q "qa"; then \
		echo "Creating QA environment backend..."; \
		./scripts/create-backend.sh qa; \
	elif echo "$$args" | grep -q "dev"; then \
		echo "Creating development environment backend..."; \
		./scripts/create-backend.sh dev; \
	elif echo "$$args" | grep -q "prod"; then \
		echo "Creating production environment backend..."; \
		./scripts/create-backend.sh prod; \
	else \
		echo "Usage: make create-backend qa|dev|prod [region]"; \
		echo "Example: make create-backend qa us-east-1"; \
		exit 1; \
	fi

init: ## Initialize Terraform modules (usage: make init qa|dev|prod)
	@args="$(filter-out $@,$(MAKECMDGOALS))"; \
	if echo "$$args" | grep -q "qa"; then \
		echo "Initializing QA environment modules..."; \
		$(MAKE) _init-modules ENV=qa; \
	elif echo "$$args" | grep -q "dev"; then \
		echo "Initializing development environment modules..."; \
		$(MAKE) _init-modules ENV=dev; \
	elif echo "$$args" | grep -q "prod"; then \
		echo "Initializing production environment modules..."; \
		$(MAKE) _init-modules ENV=prod; \
	else \
		echo "Usage: make init qa|dev|prod"; \
		echo "Note: Run 'make create-backend <env>' first to create backend resources"; \
		exit 1; \
	fi

_init-modules: ## Internal target to initialize Terraform modules for specific environment
	@echo "🔧 Initializing Terraform modules for $(ENV) environment..."
	@if [ ! -d "live/$(ENV)/us-east-1" ]; then \
		echo "❌ Environment directory 'live/$(ENV)/us-east-1' does not exist!"; \
		echo "Please create the environment directory and configuration first."; \
		exit 1; \
	fi
	@echo "📋 Running terragrunt init..."
	@cd live/$(ENV)/us-east-1 && terragrunt init --all
	@echo "✅ Module initialization completed for $(ENV) environment"


# Planning targets — scripts/plan/tg2md-plan-logs/ (tfplan2md+glow), scripts/plan/unfiltered-plan-output/ (run-all raw), scripts/plan/all-plans.md
plan: ## Plan environment (usage: make plan qa|dev|prod|production [detailed])
	@args="$(filter-out $@,$(MAKECMDGOALS))"; \
	if echo "$$args" | grep -q "qa"; then ENV=qa; \
	elif echo "$$args" | grep -q "dev"; then ENV=dev; \
	elif echo "$$args" | grep -q "prod"; then ENV=prod; \
	elif echo "$$args" | grep -q "production"; then ENV=prod; \
	else echo "Usage: make plan qa|dev|prod|production [detailed]"; exit 1; fi; \
	REPO_ROOT="$(CURDIR)"; \
	rm -rf "$$REPO_ROOT/scripts/plan" "$$REPO_ROOT/scripts/plan-artifacts"; \
	mkdir -p "$$REPO_ROOT/scripts/plan/tg2md-plan-logs" "$$REPO_ROOT/scripts/plan/unfiltered-plan-output"; \
	LIVE="$$REPO_ROOT/live"; LOGS_PLAN="$$REPO_ROOT/scripts/plan/tg2md-plan-logs"; UNFILTERED_DIR="$$REPO_ROOT/scripts/plan/unfiltered-plan-output"; TG2MD_ROOT="$$REPO_ROOT/scripts/plan-artifacts"; \
	REGION_ROOT="$$LIVE/$$ENV/us-east-1"; \
	if [ ! -d "$$REGION_ROOT" ]; then echo "Error: $$REGION_ROOT not found."; exit 1; fi; \
	mkdir -p "$$TG2MD_ROOT/$$ENV"; \
	echo "Action:  plan"; echo "Environment: $$ENV"; \
	echo "==> terragrunt run-all plan (unfiltered) -> $$UNFILTERED_DIR/$$ENV-plan.log"; \
	(cd "$$REGION_ROOT" && terragrunt run-all plan 2>&1) | tee "$$UNFILTERED_DIR/$$ENV-plan.log"; \
	echo ""; \
	STACK_CNT=0; \
	for stack_dir in $$(find "$$LIVE/$$ENV" -name "terragrunt.hcl" -type f ! -path "*/.terragrunt-cache/*" | sed 's|/terragrunt.hcl||' | sort); do \
	  rel=$$(echo "$$stack_dir" | sed "s|$$LIVE/||"); \
	  out_dir="$$TG2MD_ROOT/$$rel"; plan_tfplan="$$out_dir/plan.tfplan"; plan_json="$$out_dir/plan.json"; plan_fixed="$$out_dir/plan.tfplan2md.json"; plan_md="$$out_dir/plan.md"; \
	  mkdir -p "$$out_dir"; echo "==> $$rel (plan)"; \
	  echo "    running terragrunt plan..."; \
	  attempt=1; while true; do (cd "$$stack_dir" && TG_LOG= terragrunt plan -lock=false -out="$$plan_tfplan" -- -input=false >/dev/null 2>&1) && break; \
	    [ $$attempt -ge 3 ] && break; echo "    retry $$((attempt+1))/3..."; attempt=$$((attempt+1)); done; \
	  if [ ! -f "$$plan_tfplan" ]; then echo "    skip (no plan file)"; continue; fi; \
	  echo "    converting to markdown..."; \
	  (cd "$$stack_dir" && TG_LOG= terragrunt show -json "$$plan_tfplan" > "$$plan_json" 2>/dev/null) || true; \
	  if [ ! -s "$$plan_json" ]; then echo "    skip (no plan JSON)"; continue; fi; \
	  if command -v jq >/dev/null 2>&1; then \
	    jq 'if .resource_changes == null then . + {"resource_changes": []} else . end' "$$plan_json" > "$$plan_fixed" 2>/dev/null || cp "$$plan_json" "$$plan_fixed"; \
	  else cp "$$plan_json" "$$plan_fixed"; fi; \
	  (cd "$$out_dir" && tfplan2md --render-target github --details closed plan.tfplan2md.json > plan.md 2>/dev/null) || true; rm -f "$$plan_fixed"; \
	  if [ ! -s "$$plan_md" ]; then (cd "$$stack_dir" && TG_LOG= terragrunt show -no-color "$$plan_tfplan" > "$$plan_md" 2>/dev/null) || true; fi; \
	  if [ -s "$$plan_md" ]; then echo "    -> $$out_dir/plan.md"; else echo "# Plan: \`$$rel\`" > "$$plan_md"; echo "" >> "$$plan_md"; echo "No tfplan2md output." >> "$$plan_md"; fi; \
	  STACK_CNT=$$((STACK_CNT+1)); \
	done; \
	echo "Stacks planned: $$STACK_CNT"; echo ""; \
	ALL_PLANS="$$TG2MD_ROOT/$$ENV/ALL-PLANS.md"; \
	echo "# All Terraform plans — $$ENV" > "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; echo "Generated: $$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; echo "---" >> "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; \
	for f in $$(find "$$TG2MD_ROOT/$$ENV" -name "plan.md" -type f 2>/dev/null | sort); do \
	  rel=$$(echo "$$f" | sed "s|$$TG2MD_ROOT/$$ENV/||" | sed 's|/plan.md||'); \
	  echo "## Stack: \`$$rel\`" >> "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; \
	  sed -E 's/^[[:space:]]*[A-Za-z0-9+/=]{200,}$$/  (omitted)/g' "$$f" 2>/dev/null >> "$$ALL_PLANS" || cat "$$f" >> "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; echo "---" >> "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; \
	done; \
	if command -v glow >/dev/null 2>&1; then glow "$$ALL_PLANS" > "$$LOGS_PLAN/all-plans.md" 2>/dev/null || cp "$$ALL_PLANS" "$$LOGS_PLAN/all-plans.md"; else cp "$$ALL_PLANS" "$$LOGS_PLAN/all-plans.md" 2>/dev/null || true; fi; \
	cp -f "$$LOGS_PLAN/all-plans.md" "$$REPO_ROOT/scripts/plan/all-plans.md" 2>/dev/null || true; \
	for f in $$(find "$$TG2MD_ROOT/$$ENV" -name "plan.md" -type f 2>/dev/null | sort); do \
	  rel=$$(echo "$$f" | sed "s|$$TG2MD_ROOT/$$ENV/||" | sed 's|/plan.md||'); slug=$$(echo "$$rel" | tr '/' '-'); \
	  if command -v glow >/dev/null 2>&1; then glow "$$f" > "$$LOGS_PLAN/$$slug.log" 2>/dev/null || cp "$$f" "$$LOGS_PLAN/$$slug.log"; else cp "$$f" "$$LOGS_PLAN/$$slug.log"; fi; echo "Log: $$LOGS_PLAN/$$slug.log"; \
	done; \
	echo "Done. Combined plan: $$LOGS_PLAN/all-plans.md (copy: $$REPO_ROOT/scripts/plan/all-plans.md)"; echo "View: glow $$LOGS_PLAN/all-plans.md"; \
	rm -rf "$$TG2MD_ROOT"; echo "Cleaned up scripts/plan-artifacts (outputs under scripts/plan/ are fresh for this env)."

fix-providers: ## chmod +x all terraform-provider-* (fixes permission denied after S3 restore)
	@chmod +x ./scripts/fix-terraform-provider-perms.sh 2>/dev/null || true
	@./scripts/fix-terraform-provider-perms.sh

# Apply targets
apply: ## Apply environment (usage: make apply qa|dev|prod [auto-approve] [detailed])
	@args="$(filter-out $@,$(MAKECMDGOALS))"; \
	if echo "$$args" | grep -q "qa"; then \
		detailed_flag=""; \
		if echo "$$args" | grep -q "detailed"; then detailed_flag="--detailed"; fi; \
		if echo "$$args" | grep -q "auto-approve"; then \
			echo "Applying QA environment with auto-approve..."; \
			./scripts/tg-summarize apply live/qa/us-east-1 --auto-approve $$detailed_flag; \
		else \
			echo "Applying QA environment..."; \
			./scripts/tg-summarize apply live/qa/us-east-1 $$detailed_flag; \
		fi; \
	elif echo "$$args" | grep -q "dev"; then \
		detailed_flag=""; \
		if echo "$$args" | grep -q "detailed"; then detailed_flag="--detailed"; fi; \
		if echo "$$args" | grep -q "auto-approve"; then \
			echo "Applying development environment with auto-approve..."; \
			./scripts/tg-summarize apply live/dev/us-east-1 --auto-approve $$detailed_flag; \
		else \
			echo "Applying development environment..."; \
			./scripts/tg-summarize apply live/dev/us-east-1 $$detailed_flag; \
		fi; \
	elif echo "$$args" | grep -q "prod"; then \
		detailed_flag=""; \
		if echo "$$args" | grep -q "detailed"; then detailed_flag="--detailed"; fi; \
		if echo "$$args" | grep -q "auto-approve"; then \
			echo "Applying production environment with auto-approve..."; \
			./scripts/tg-summarize apply live/prod/us-east-1 --auto-approve $$detailed_flag; \
		else \
			echo "Applying production environment..."; \
			./scripts/tg-summarize apply live/prod/us-east-1 $$detailed_flag; \
		fi; \
	else \
		echo "Usage: make apply qa|dev|prod [auto-approve] [detailed]"; \
		exit 1; \
	fi

# Comparison targets
compare: ## Compare configurations (usage: make compare <source> <destination>)
	@if [ "$(filter-out $@,$(MAKECMDGOALS))" = "" ]; then \
		echo "Comparing QA and production configurations..."; \
		./scripts/tg-compare live/qa/ live/prod/; \
	else \
		args="$(filter-out $@,$(MAKECMDGOALS))"; \
		arg_count=$$(echo "$$args" | wc -w); \
		if [ "$$arg_count" -ne 2 ]; then \
			echo "Usage: make compare <source> <destination>"; \
			echo "Example: make compare live/qa live/prod"; \
			exit 1; \
		fi; \
		echo "Comparing $$args..."; \
		./scripts/tg-compare $$args; \
	fi

# Handle arguments (prevent them from being treated as targets)
qa dev prod live/qa live/dev live/prod auto-approve detailed ENV:
	@:

# Documentation targets
docs: ## Generate documentation for all modules
	@echo "Generating module documentation..."
	@find modules -name "main.tf" -exec terraform-docs markdown table {} \; > /dev/null

# Cleanup targets
clean: ## Clean all cache directories, lock files, and temporary files
	@echo "Cleaning all cache directories, lock files, and temporary files..."
	@find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terragrunt-cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.tfplan" -delete 2>/dev/null || true
	@find . -name "*.tfstate*" -delete 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@rm -f tg-compare.txt terragrunt-*.log 2>/dev/null || true

cache-size: ## Show cache size and provider usage
	@echo "Cache size analysis:"
	@echo "==================="
	@if [ -d ".terragrunt-cache" ]; then \
		echo "Terragrunt cache size: $$(du -sh .terragrunt-cache 2>/dev/null | cut -f1)"; \
	else \
		echo "No .terragrunt-cache directory found"; \
	fi
	@echo ""
	@echo "Provider cache size:"
	@find . -name ".terraform" -type d -exec du -sh {} \; 2>/dev/null | head -10
	@echo ""
	@echo "Total provider cache size: $$(find . -name ".terraform" -type d -exec du -s {} \; 2>/dev/null | awk '{sum += $$1} END {print sum/1024/1024 " MB"}')"

# Pre-commit setup
install-hooks: ## Install pre-commit hooks
	@pre-commit install

# Environment setup
setup: ## Initial setup for development
	@echo "Setting up development environment..."
	@terraform --version
	@terragrunt --version
	@tflint --version
	@checkov --version
	@echo "Development environment ready!"