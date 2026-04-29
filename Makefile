# Makefile for valpay-aws-terraform
.PHONY: help validate plan apply destroy clean fmt lint docs compare create-backend init _init-modules fix-providers _ensure-tfplan2md install-tfplan2md

# Pin with CI (.github/workflows/terragrunt-plan.yml TFPLAN2MD_VERSION)
TFPLAN2MD_VERSION ?= 1.42.0
# tfplan2md: github target still injects AZDO-style <details style="...">; bitbucket is markdown-only (no palette CSS)
TFPLAN2MD_RENDER_TARGET ?= bitbucket


# Default target
help: ## Show this help message
	@echo "Available targets:"
	@echo "  make create-backend <env> - Create backend resources (qa, dev, prod)"
	@echo "  make init <env>           - Initialize Terraform modules (qa, dev, prod)"
	@echo "  make plan <env>           - Plan environment (qa, dev, prod)"
	@echo "  make install-tfplan2md      - Install native tfplan2md under .tools/bin (optional; plan auto-installs if needed)"
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


# Native tfplan2md (PATH often has a Docker wrapper — fails without Docker). Pin matches .github/workflows/terragrunt-plan.yml default.
_ensure-tfplan2md:
	@REPO_ROOT="$(CURDIR)"; TOOLS_BIN="$$REPO_ROOT/.tools/bin"; VERSION="$(TFPLAN2MD_VERSION)"; \
	mkdir -p "$$TOOLS_BIN"; \
	if [ -n "$$TFPLAN2MD" ] && [ -x "$$TFPLAN2MD" ]; then echo "tfplan2md: using TFPLAN2MD=$$TFPLAN2MD"; exit 0; fi; \
	PF=$$(command -v tfplan2md 2>/dev/null || true); \
	if [ -n "$$PF" ] && [ -f "$$PF" ] && ! head -1 "$$PF" 2>/dev/null | grep -q '^#!'; then echo "tfplan2md: using native $$PF"; exit 0; fi; \
	if [ -x "$$TOOLS_BIN/tfplan2md" ]; then echo "tfplan2md: using $$TOOLS_BIN/tfplan2md"; exit 0; fi; \
	echo "tfplan2md: downloading v$$VERSION -> $$TOOLS_BIN ..."; \
	TGZ="tfplan2md_$${VERSION}_linux-x64.tar.gz"; URL="https://github.com/oocx/tfplan2md/releases/download/v$${VERSION}/$${TGZ}"; \
	if command -v curl >/dev/null 2>&1; then curl -fsSL -o "/tmp/$$TGZ" "$$URL"; \
	elif command -v wget >/dev/null 2>&1; then wget -q -O "/tmp/$$TGZ" "$$URL"; \
	else echo "Need curl or wget to bootstrap tfplan2md."; exit 1; fi; \
	tar -xzf "/tmp/$$TGZ" -C /tmp && install -m 0755 /tmp/tfplan2md "$$TOOLS_BIN/tfplan2md" && rm -f "/tmp/$$TGZ" /tmp/tfplan2md; \
	echo "tfplan2md: installed $$TOOLS_BIN/tfplan2md"

install-tfplan2md: ## Install native tfplan2md to .tools/bin (override TFPLAN2MD_VERSION= to match CI)
	@rm -f "$(CURDIR)/.tools/bin/tfplan2md"
	@$(MAKE) _ensure-tfplan2md

# Planning targets — only scripts/plan/tg2md-plan/ and scripts/plan/unfiltered-plan/:
#   unfiltered-plan/all-plans.md = concatenated raw terragrunt plan logs per stack (each stack uses terragrunt.hcl → root.hcl); ANSI/timestamps stripped
#   tg2md-plan/*.md = tfplan2md only (all-plans.md + per-stack); temp tfplan/json under plan-artifacts (deleted)
# Do not use `terragrunt plan ... -- -input=false`: Terraform then treats post-`--` args as positionals → "Too many command line arguments" (TF 1.14+).
# Pipe JSON on stdin per upstream README. Override: TFPLAN2MD=/path/to/native/binary
plan: _ensure-tfplan2md ## Plan environment (usage: make plan qa|dev|prod|production [detailed])
	@args="$(filter-out $@,$(MAKECMDGOALS))"; \
	if echo "$$args" | grep -q "qa"; then ENV=qa; \
	elif echo "$$args" | grep -q "dev"; then ENV=dev; \
	elif echo "$$args" | grep -q "prod"; then ENV=prod; \
	elif echo "$$args" | grep -q "production"; then ENV=prod; \
	else echo "Usage: make plan qa|dev|prod|production [detailed]"; exit 1; fi; \
	REPO_ROOT="$(CURDIR)"; \
	rm -rf "$$REPO_ROOT/scripts/plan" "$$REPO_ROOT/scripts/plan-artifacts"; \
	mkdir -p "$$REPO_ROOT/scripts/plan/tg2md-plan" "$$REPO_ROOT/scripts/plan/unfiltered-plan"; \
	LIVE="$$REPO_ROOT/live"; LOGS_PLAN="$$REPO_ROOT/scripts/plan/tg2md-plan"; UNFILTERED_DIR="$$REPO_ROOT/scripts/plan/unfiltered-plan"; TG2MD_ROOT="$$REPO_ROOT/scripts/plan-artifacts"; \
	PF=$$(command -v tfplan2md 2>/dev/null || true); \
	if [ -n "$${TFPLAN2MD:-}" ] && [ -x "$${TFPLAN2MD}" ]; then TFMD="$${TFPLAN2MD}"; \
	elif [ -n "$$PF" ] && [ -f "$$PF" ] && ! head -1 "$$PF" 2>/dev/null | grep -q '^#!'; then TFMD="$$PF"; \
	elif [ -x "$$REPO_ROOT/.tools/bin/tfplan2md" ]; then TFMD="$$REPO_ROOT/.tools/bin/tfplan2md"; \
	else TFMD="$$PF"; fi; \
	if [ -z "$$TFMD" ] || [ ! -x "$$TFMD" ]; then echo "tfplan2md not found; run: make install-tfplan2md"; exit 1; fi; \
	if head -1 "$$TFMD" 2>/dev/null | grep -q '^#!'; then echo "tfplan2md at $$TFMD is a shell wrapper; run: make install-tfplan2md or set TFPLAN2MD to the native binary."; exit 1; fi; \
	echo "Using tfplan2md: $$TFMD"; \
	if [ ! -d "$$LIVE/$$ENV/us-east-1" ]; then echo "Error: $$LIVE/$$ENV/us-east-1 not found."; exit 1; fi; \
	mkdir -p "$$TG2MD_ROOT/$$ENV"; \
	UNF_TMP="$$TG2MD_ROOT/unfiltered-combined.raw"; : > "$$UNF_TMP"; \
	echo "Action:  plan"; echo "Environment: $$ENV"; \
	echo "==> Raw per-stack \`terragrunt plan\` -> $$UNFILTERED_DIR/all-plans.md (ANSI + TG timestamps stripped)"; \
	echo "==> tfplan2md -> $$LOGS_PLAN/*.md (markdown only)"; \
	echo ""; \
	STACK_CNT=0; \
	for stack_dir in $$(find "$$LIVE/$$ENV" -name "terragrunt.hcl" -type f ! -path "*/.terragrunt-cache/*" | sed 's|/terragrunt.hcl||' | sort); do \
	  rel=$$(echo "$$stack_dir" | sed "s|$$LIVE/||"); slug=$$(echo "$$rel" | tr '/' '-'); \
	  out_dir="$$TG2MD_ROOT/$$rel"; plan_tfplan="$$out_dir/plan.tfplan"; plan_json="$$out_dir/plan.json"; plan_md="$$out_dir/plan.md"; \
	  TG_STACK_LOG="$$out_dir/plan-terragrunt.log"; \
	  mkdir -p "$$out_dir"; echo "==> $$rel (plan)"; \
	  echo "    running terragrunt plan (log temp, removed with plan-artifacts)..."; \
	  : > "$$TG_STACK_LOG"; \
	  attempt=1; \
	  while [ $$attempt -le 3 ]; do \
	    echo "" >> "$$TG_STACK_LOG"; echo "==== attempt $$attempt $$(date -u +%Y-%m-%dT%H:%M:%SZ) stack=$$rel ====" >> "$$TG_STACK_LOG"; \
	    (cd "$$stack_dir" && terragrunt plan -input=false -lock=false -out="$$plan_tfplan") >> "$$TG_STACK_LOG" 2>&1; \
	    plan_exit=$$?; echo "==== terragrunt exit code: $$plan_exit ====" >> "$$TG_STACK_LOG"; \
	    if [ -f "$$plan_tfplan" ]; then break; fi; \
	    if [ $$attempt -ge 3 ]; then break; fi; \
	    echo "    retry $$((attempt+1))/3..."; attempt=$$((attempt+1)); \
	  done; \
	  echo "===== stack: $$rel =====" >> "$$UNF_TMP"; \
	  cat "$$TG_STACK_LOG" >> "$$UNF_TMP"; echo "" >> "$$UNF_TMP"; \
	  if [ ! -f "$$plan_tfplan" ]; then \
	    echo "    skip (no plan file) — same stack log appended to unfiltered-plan/all-plans.md"; \
	    echo "    --- last 45 lines of terragrunt output ---"; \
	    tail -n 45 "$$TG_STACK_LOG" 2>/dev/null || true; \
	    continue; \
	  fi; \
	  echo "    converting to markdown..."; \
	  (cd "$$stack_dir" && TG_LOG= terragrunt show -json "$$plan_tfplan" > "$$plan_json" 2>/dev/null) || true; \
	  if [ ! -s "$$plan_json" ]; then echo "    skip (no plan JSON)"; continue; fi; \
	  if command -v jq >/dev/null 2>&1; then \
	    jq 'if .resource_changes == null then . + {"resource_changes": []} else . end' "$$plan_json" \
	      | "$$TFMD" --render-target "$(TFPLAN2MD_RENDER_TARGET)" --details closed > "$$plan_md" 2>"$$out_dir/tfplan2md.stderr" || true; \
	  else \
	    cat "$$plan_json" | "$$TFMD" --render-target "$(TFPLAN2MD_RENDER_TARGET)" --details closed > "$$plan_md" 2>"$$out_dir/tfplan2md.stderr" || true; \
	  fi; \
	  if [ ! -s "$$plan_md" ] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
	    if command -v jq >/dev/null 2>&1; then \
	      jq 'if .resource_changes == null then . + {"resource_changes": []} else . end' "$$plan_json" \
	        | docker run -i --rm oocx/tfplan2md:latest --render-target "$(TFPLAN2MD_RENDER_TARGET)" --details closed > "$$plan_md" 2>"$$out_dir/tfplan2md.docker.stderr" || true; \
	    else \
	      cat "$$plan_json" | docker run -i --rm oocx/tfplan2md:latest --render-target "$(TFPLAN2MD_RENDER_TARGET)" --details closed > "$$plan_md" 2>"$$out_dir/tfplan2md.docker.stderr" || true; \
	    fi; \
	  fi; \
	  if [ ! -s "$$plan_md" ]; then \
	    echo "# tfplan2md failed — \`$$rel\`" > "$$plan_md"; echo "" >> "$$plan_md"; \
	    echo "Expected: markdown tables from \`terraform show -json\` via [tfplan2md](https://github.com/oocx/tfplan2md). Install the **linux-x64 release tarball** binary, or run Docker, or set \`TFPLAN2MD=/path/to/tfplan2md\` if your \`tfplan2md\` command is only a Docker wrapper." >> "$$plan_md"; echo "" >> "$$plan_md"; \
	    echo "**stderr (native):**" >> "$$plan_md"; echo '```' >> "$$plan_md"; cat "$$out_dir/tfplan2md.stderr" 2>/dev/null >> "$$plan_md"; echo '```' >> "$$plan_md"; \
	    if [ -s "$$out_dir/tfplan2md.docker.stderr" ]; then echo "" >> "$$plan_md"; echo "**stderr (docker):**" >> "$$plan_md"; echo '```' >> "$$plan_md"; cat "$$out_dir/tfplan2md.docker.stderr" >> "$$plan_md"; echo '```' >> "$$plan_md"; fi; \
	  else echo "    -> tfplan2md -> $$plan_md"; fi; \
	  STACK_CNT=$$((STACK_CNT+1)); \
	done; \
	{ \
	  echo "# Raw terragrunt plan (concatenated per stack; includes root.hcl via each stack terragrunt.hcl)"; \
	  echo "# env=$$ENV  tfplan2md_stacks=$$STACK_CNT  $$(date -u +%Y-%m-%dT%H:%M:%SZ)"; \
	  echo ""; \
	} > "$$UNFILTERED_DIR/all-plans.md"; \
	sed -E 's/\x1b\[[0-9;]*m//g; s/\x1b\[[0-9;]*[a-zA-Z]//g' "$$UNF_TMP" \
	  | sed -E 's/^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}[[:space:]]+//' >> "$$UNFILTERED_DIR/all-plans.md"; \
	rm -f "$$UNF_TMP"; \
	echo "Stacks planned (tfplan2md): $$STACK_CNT"; echo ""; \
	ALL_PLANS="$$TG2MD_ROOT/$$ENV/ALL-PLANS.md"; \
	echo "# All Terraform plans — $$ENV" > "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; echo "Generated: $$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; echo "---" >> "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; \
	for f in $$(find "$$TG2MD_ROOT/$$ENV" -name "plan.md" -type f 2>/dev/null | sort); do \
	  rel=$$(echo "$$f" | sed "s|$$TG2MD_ROOT/$$ENV/||" | sed 's|/plan.md||'); \
	  echo "## Stack: \`$$rel\`" >> "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; \
	  sed -E 's/^[[:space:]]*[A-Za-z0-9+/=]{200,}$$/  (omitted)/g' "$$f" 2>/dev/null >> "$$ALL_PLANS" || cat "$$f" >> "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; echo "---" >> "$$ALL_PLANS"; echo "" >> "$$ALL_PLANS"; \
	done; \
	cp -f "$$ALL_PLANS" "$$LOGS_PLAN/all-plans.md" 2>/dev/null || true; \
	for f in $$(find "$$TG2MD_ROOT/$$ENV" -name "plan.md" -type f 2>/dev/null | sort); do \
	  rel=$$(echo "$$f" | sed "s|$$TG2MD_ROOT/$$ENV/||" | sed 's|/plan.md||'); slug=$$(echo "$$rel" | tr '/' '-'); \
	  cp -f "$$f" "$$LOGS_PLAN/$$slug.md"; echo "Wrote: $$LOGS_PLAN/$$slug.md"; \
	done; \
	echo "Done. Raw combined plans: $$UNFILTERED_DIR/all-plans.md | Combined tfplan2md: $$LOGS_PLAN/all-plans.md"; \
	echo "View raw: less $$UNFILTERED_DIR/all-plans.md"; \
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