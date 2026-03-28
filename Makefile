# OpenClaw — macOS hardening toolkit
# Usage: make help
#
# Naming convention: noun-verb (e.g., agents-setup, agents-teardown)
# This groups related targets together in sorted `make help` output.

SHELL := /bin/bash
SCRIPTS := scripts
COMPOSE := $(SCRIPTS)/templates/docker-compose.yml
PREFIX := /opt/n8n
OPENCLAW_DIR := $(HOME)/.openclaw

.PHONY: help install uninstall verify doctor audit \
	fix fix-interactive fix-dry-run fix-undo \
	gateway-setup gateway-teardown \
	shellrc-setup shellrc-teardown \
	openclaw-setup \
	runtime-setup \
	ollama-model-setup ollama-model-teardown \
	agents-setup agents-teardown \
	hmac-setup hmac-teardown \
	hooks-setup hooks-teardown \
	manifest-update manifest-clean \
	workflow-export workflow-import workflow-clean \
	m3-teardown \
	integrity-deploy integrity-lock integrity-unlock integrity-verify \
	sandbox-setup sandbox-teardown \
	monitor-setup monitor-teardown monitor-status \
	skillallow-add skillallow-remove \
	container-security-config-update \
	security-tools-setup security-update-hashes container-bench n8n-audit scan-image security \
	integrity-rotate-key \
	setup-gateway teardown-gateway shellrc shellrc-undo

help: ## Show available targets
	@grep -E '^[a-z0-9_-]+:.*##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ===========================================================================
# Core — M1/M2 targets
# ===========================================================================

install: ## Prepare macOS: install tools, create directories, deploy scripts
	bash $(SCRIPTS)/bootstrap.sh

audit: ## Run security audit, display results, and save JSON (requires sudo)
	@sudo bash $(SCRIPTS)/hardening-audit.sh || true
	@sudo bash $(SCRIPTS)/hardening-audit.sh --json | sudo tee $(PREFIX)/logs/audit/audit-$$(date +%Y%m%d-%H%M%S).json > /dev/null
	@echo ""
	@echo "Audit results saved. Run 'make fix' to apply fixes."

verify: ## Check that all expected artifacts are present
	@echo "OpenClaw Verify"
	@echo "==============="
	@brew bundle check --file=Brewfile 2>/dev/null && echo "  OK  Brew packages" || echo "  MISSING  Some brew packages (run: make install)"
	@for f in hardening-audit.sh hardening-fix.sh audit-notify.sh audit-cron.sh; do \
		[ -f "$(PREFIX)/scripts/$$f" ] && printf "  OK  %s\n" "$(PREFIX)/scripts/$$f" || printf "  MISSING  %s\n" "$(PREFIX)/scripts/$$f"; \
	done
	@sudo -n test -f "$(PREFIX)/etc/notify.conf" 2>/dev/null \
		&& echo "  OK  $(PREFIX)/etc/notify.conf" \
		|| (sudo test -f "$(PREFIX)/etc/notify.conf" 2>/dev/null \
			&& echo "  OK  $(PREFIX)/etc/notify.conf" \
			|| echo "  MISSING  notify.conf")
	@[ -d "$(PREFIX)" ] && echo "  OK  $(PREFIX)/ exists" || echo "  MISSING  $(PREFIX)/"
	@colima status 2>/dev/null && echo "  OK  Colima running" || echo "  DOWN  Colima not running"
	@docker ps 2>/dev/null | grep -q n8n && echo "  OK  n8n container running" || echo "  DOWN  n8n container not running"
	@[ -f "$(OPENCLAW_DIR)/shellrc" ] && echo "  OK  Shell aliases" || echo "  MISSING  Shell aliases (run: make shellrc-setup)"
	@command -v grype >/dev/null 2>&1 && echo "  OK  Grype (CVE scanner)" || echo "  MISSING  Grype (run: make security-tools-setup)"
	@[ -d "$(HOME)/.openclaw/tools/docker-bench-security" ] && echo "  OK  docker-bench-security (CIS benchmark)" || echo "  MISSING  docker-bench-security (run: make security-tools-setup)"

doctor: ## Check all prerequisite tools are installed
	@bash $(SCRIPTS)/doctor.sh

# --- Fix targets ---

fix: ## Apply safe hardening fixes without prompts (requires sudo)
	@sudo bash $(SCRIPTS)/hardening-audit.sh --json | sudo tee $(PREFIX)/logs/audit/audit-$$(date +%Y%m%d-%H%M%S).json > /dev/null
	@sudo bash $(SCRIPTS)/hardening-fix.sh --auto || true

fix-interactive: ## Apply hardening fixes one at a time with approval (requires sudo)
	@sudo bash $(SCRIPTS)/hardening-audit.sh --json | sudo tee $(PREFIX)/logs/audit/audit-$$(date +%Y%m%d-%H%M%S).json > /dev/null
	@sudo bash $(SCRIPTS)/hardening-fix.sh --interactive || true

fix-dry-run: ## Preview fixes without applying them (requires sudo)
	@sudo bash $(SCRIPTS)/hardening-audit.sh --json | sudo tee $(PREFIX)/logs/audit/audit-$$(date +%Y%m%d-%H%M%S).json > /dev/null
	@sudo bash $(SCRIPTS)/hardening-fix.sh --dry-run --auto || true

fix-undo: ## Undo the most recent fix run using its restore script
	@LATEST=$$(ls -t $(PREFIX)/logs/audit/pre-fix-restore-*.sh 2>/dev/null | head -1); \
	if [ -z "$$LATEST" ]; then \
		LATEST=$$(ls -t $(OPENCLAW_DIR)/restore-scripts/pre-fix-restore-*.sh 2>/dev/null | head -1); \
	fi; \
	if [ -z "$$LATEST" ]; then \
		echo "No restore scripts found. Run 'make fix' first."; \
		exit 1; \
	fi; \
	echo "Restore script: $$LATEST"; \
	echo ""; \
	sudo bash "$$LATEST" --list; \
	echo ""; \
	read -p "Undo all changes from this run? [y/N] " confirm; \
	if [ "$$confirm" = "y" ]; then \
		sudo bash "$$LATEST" --all; \
	else \
		echo "Aborted. To undo a single check: sudo bash $$LATEST CHK-ID"; \
	fi

# --- Gateway (M1) ---

gateway-setup: ## Start Colima, deploy n8n container, configure secrets
	bash $(SCRIPTS)/gateway-setup.sh

gateway-teardown: ## Stop and remove n8n container and Colima VM
	-@docker compose -f $(COMPOSE) down -v 2>/dev/null && echo "Removed n8n containers and volumes" || echo "No n8n containers found"
	-@colima stop 2>/dev/null && echo "Stopped Colima" || echo "Colima not running"

# --- Shell aliases ---

shellrc-setup: ## Set up openclaw aliases in ~/.openclaw/shellrc
	@mkdir -p $(OPENCLAW_DIR)
	@REPO_ROOT="$$(cd "$$(dirname "$(MAKEFILE_LIST)")" && pwd)"; \
	printf '# OpenClaw Shell Configuration\n# Source: %s/Makefile shellrc-setup target\n# To undo: make shellrc-teardown\n\nalias openclaw-audit='\''sudo bash %s/scripts/hardening-audit.sh'\''\nalias openclaw-fix='\''sudo bash %s/scripts/hardening-fix.sh --interactive'\''\nalias n8n-token='\''security find-generic-password -a "openclaw" -s "n8n-gateway-bearer" -w'\''\n' \
		"$$REPO_ROOT" "$$REPO_ROOT" "$$REPO_ROOT" > $(OPENCLAW_DIR)/shellrc
	@RC_FILE="$$( [[ "$$(basename "$$SHELL")" == "bash" ]] && echo "$$HOME/.bash_profile" || echo "$$HOME/.zshrc" )"; \
	grep -qF 'openclaw/shellrc' "$$RC_FILE" 2>/dev/null || \
		printf '\n[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc\n' >> "$$RC_FILE"; \
	echo "Aliases installed. Run: source $$RC_FILE"
	@echo "Note: Aliases use absolute paths to this repo. If you move the repo, re-run 'make shellrc-setup'."

shellrc-teardown: ## Remove openclaw shell aliases
	@rm -f $(OPENCLAW_DIR)/shellrc
	@for f in ~/.zshrc ~/.bash_profile; do [ -f "$$f" ] && sed -i '' '/openclaw\/shellrc/d' "$$f" 2>/dev/null; done; true
	@echo "Shell aliases removed. Restart your terminal or run: exec $$SHELL"

# --- Uninstall (full) ---

uninstall: ## Remove all openclaw artifacts (keeps hardening — use restore script)
	@echo "OpenClaw Uninstall"
	@echo "=================="
	@echo ""
	@echo "This will remove openclaw tooling. Hardening changes are NOT reversed."
	@echo "To undo hardening first, run: make fix-undo"
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || { echo "Aborted."; exit 1; }
	@echo ""
	@if ls $(PREFIX)/logs/audit/pre-fix-restore-*.sh 1>/dev/null 2>&1; then \
		mkdir -p $(OPENCLAW_DIR)/restore-scripts; \
		sudo cp $(PREFIX)/logs/audit/pre-fix-restore-*.sh $(OPENCLAW_DIR)/restore-scripts/; \
		echo "  Preserved restore scripts in $(OPENCLAW_DIR)/restore-scripts/"; \
	fi
	@docker compose -f $(COMPOSE) down -v 2>/dev/null || true
	@echo "  Removed Docker containers and volumes"
	@colima stop 2>/dev/null || true
	@colima delete --force 2>/dev/null || true
	@echo "  Removed Colima VM"
	@sudo launchctl bootout system/com.openclaw.audit-cron 2>/dev/null || true
	@sudo rm -f /Library/LaunchDaemons/com.openclaw.audit-cron.plist
	@echo "  Removed launchd plist"
	@security delete-generic-password -s n8n-gateway-bearer >/dev/null 2>&1 || true
	@echo "  Removed keychain entry"
	@sudo rm -rf $(PREFIX)
	@echo "  Removed $(PREFIX)/"
	@rm -f $(OPENCLAW_DIR)/shellrc
	@for f in ~/.zshrc ~/.bash_profile; do [ -f "$$f" ] && sed -i '' '/openclaw\/shellrc/d' "$$f" 2>/dev/null; done; true
	@echo "  Removed shell aliases"
	@echo ""
	@echo "Done. Brew packages left in place (remove manually: brew bundle cleanup --file=Brewfile --force)"
	@if ls $(OPENCLAW_DIR)/restore-scripts/pre-fix-restore-*.sh 1>/dev/null 2>&1; then \
		echo "Restore scripts preserved in: $(OPENCLAW_DIR)/restore-scripts/"; \
	fi

# ===========================================================================
# M3: OpenClaw Agent Targets — LinkedIn Automation
#
# Naming: noun-verb (groups related targets in sorted help output)
#
# Paired install/teardown targets for incremental validation:
#   runtime-setup → ollama-model-setup → agents-setup → hmac-setup →
#   hooks-setup → docker-image-setup → workflow-import
#
# Undo in reverse:
#   workflow-clean → docker-image-teardown → hooks-teardown →
#   hmac-teardown → agents-teardown → ollama-model-teardown
#
# runtime-setup has NO teardown — Bun/OpenClaw/Ollama are shared system
# tools. Removing them could break unrelated projects. Remove manually
# if nothing else depends on them:
#   rm -rf ~/.bun && brew uninstall ollama
# ===========================================================================

# --- Composite ---

openclaw-setup: ## M3: Full setup — install runtimes, agents, secrets, Docker image
	bash $(SCRIPTS)/openclaw-setup.sh

# --- Granular paired targets ---

runtime-setup: ## M3: Install Bun, OpenClaw, Ollama (NO undo — shared tools)
	@echo "Installing shared runtimes (no teardown — these are shared system tools)..."
	@command -v bun >/dev/null 2>&1 || (curl -fsSL https://bun.sh/install | bash)
	@command -v openclaw >/dev/null 2>&1 || (export PATH="$$HOME/.bun/bin:$$PATH" && bun install -g openclaw)
	@command -v ollama >/dev/null 2>&1 || brew install ollama
	@echo ""
	@echo "Runtimes installed. No teardown target — shared tools."
	@echo "Manual removal: rm -rf ~/.bun && brew uninstall ollama"
	@echo ""
	@echo "NOTE: If this is a new shell, run: source ~/.bash_profile"
	@echo "      (Bun adds itself to PATH in .bash_profile, but the current shell needs a reload)"

ollama-model-setup: ## M3: Pull llama3.3 model for local LLM fallback (~4GB)
	@if ollama list 2>/dev/null | grep -q "llama3.3"; then \
		echo "llama3.3 already available"; \
	else \
		echo "Pulling llama3.3 (~4GB)..."; \
		brew services start ollama 2>/dev/null || true; \
		sleep 2; \
		ollama pull llama3.3; \
	fi

ollama-model-teardown: ## M3: Remove llama3.3 model (frees ~4GB)
	@ollama rm llama3.3 2>/dev/null && echo "Removed llama3.3 model" || echo "llama3.3 not found"

agents-setup: ## M3: Create agents and deploy workspace files
	@echo "Creating agents and deploying workspace files..."
	@command -v openclaw >/dev/null 2>&1 || { echo "Error: OpenClaw not installed. Run: make runtime-setup"; exit 1; }
	@NODE_VER=$$(node --version 2>/dev/null | sed 's/^v//'); \
	NODE_MAJOR=$$(echo "$$NODE_VER" | cut -d. -f1); \
	NODE_MINOR=$$(echo "$$NODE_VER" | cut -d. -f2); \
	if [ -z "$$NODE_VER" ]; then \
		echo "Error: Node.js not found. Install: brew install node@22"; exit 1; \
	elif [ "$$NODE_MAJOR" -lt 22 ] || { [ "$$NODE_MAJOR" -eq 22 ] && [ "$$NODE_MINOR" -lt 16 ]; }; then \
		echo "Error: Node.js $$NODE_VER too old. OpenClaw requires >=22.16.0"; \
		echo "Upgrade: brew upgrade node"; exit 1; \
	fi
	@[ -d "$(OPENCLAW_DIR)/agents/linkedin-persona" ] || \
		openclaw agents add linkedin-persona --non-interactive --workspace "$(OPENCLAW_DIR)/agents/linkedin-persona"
	@if [ -d "$(OPENCLAW_DIR)/agents/linkedin-persona" ]; then \
		cp openclaw/*.md $(OPENCLAW_DIR)/agents/linkedin-persona/; \
		mkdir -p $(OPENCLAW_DIR)/agents/linkedin-persona/skills; \
		cp -Rp openclaw/skills/linkedin-post openclaw/skills/linkedin-activity openclaw/skills/token-status \
			$(OPENCLAW_DIR)/agents/linkedin-persona/skills/; \
		echo "  Deployed workspace files to linkedin-persona"; \
	else \
		echo "  ERROR: linkedin-persona agent dir not found"; exit 1; \
	fi
	@echo "Done. Undo: make agents-teardown"

agents-teardown: ## M3: Remove agent directories and workspace files
	@echo "Removing M3 agents..."
	@openclaw agents delete linkedin-persona --force 2>/dev/null && echo "  Deregistered linkedin-persona from openclaw.json" || true
	@rm -rf $(OPENCLAW_DIR)/agents/linkedin-persona && echo "  Removed linkedin-persona directory" || true
	@echo "Done."

hmac-setup: ## M3: Generate and distribute HMAC shared secret
	bash $(SCRIPTS)/hmac-keygen.sh

hmac-teardown: ## M3: Remove HMAC secrets from .env files
	@echo "Removing HMAC secrets..."
	@if [ -f "$(OPENCLAW_DIR)/.env" ]; then \
		sed -i '' '/^N8N_WEBHOOK_SECRET=/d' $(OPENCLAW_DIR)/.env 2>/dev/null; \
		echo "  Removed N8N_WEBHOOK_SECRET from $(OPENCLAW_DIR)/.env"; \
	fi
	@if [ -f ".env" ]; then \
		sed -i '' '/^OPENCLAW_WEBHOOK_SECRET=/d' .env 2>/dev/null; \
		echo "  Removed OPENCLAW_WEBHOOK_SECRET from .env"; \
	fi
	@echo "Done. Restart n8n to clear from its environment."

hooks-setup: ## M3: Configure OpenClaw inbound hooks in openclaw.json
	@echo "Configuring inbound hooks..."
	@if [ ! -f "$(OPENCLAW_DIR)/openclaw.json" ]; then \
		echo "Error: $(OPENCLAW_DIR)/openclaw.json not found. Run: make agents-setup"; exit 1; \
	fi
	@if jq -e '.hooks.enabled' $(OPENCLAW_DIR)/openclaw.json >/dev/null 2>&1; then \
		echo "Hooks already configured"; \
	else \
		TOKEN=$$(openssl rand -hex 32); \
		TMP=$$(mktemp "$(HOME)/.openclaw/tmp/atomic-XXXXXX"); \
		jq --arg token "$$TOKEN" '. + {"hooks": {"enabled": true, "token": $$token, "path": "/hooks"}}' \
			$(OPENCLAW_DIR)/openclaw.json > "$$TMP" && mv "$$TMP" $(OPENCLAW_DIR)/openclaw.json; \
		[ -f "$(OPENCLAW_DIR)/.env" ] || (touch $(OPENCLAW_DIR)/.env && chmod 600 $(OPENCLAW_DIR)/.env); \
		echo "OPENCLAW_HOOK_TOKEN=$$TOKEN" >> $(OPENCLAW_DIR)/.env; \
		echo "  Hooks configured (token: $${TOKEN:0:8}...)"; \
	fi
	@echo "Done. Undo: make hooks-teardown"

hooks-teardown: ## M3: Remove hook config from openclaw.json and .env
	@echo "Removing hook configuration..."
	@if [ -f "$(OPENCLAW_DIR)/openclaw.json" ]; then \
		TMP=$$(mktemp "$(HOME)/.openclaw/tmp/atomic-XXXXXX"); \
		jq 'del(.hooks)' $(OPENCLAW_DIR)/openclaw.json > "$$TMP" && mv "$$TMP" $(OPENCLAW_DIR)/openclaw.json; \
		echo "  Removed .hooks from openclaw.json"; \
	fi
	@if [ -f "$(OPENCLAW_DIR)/.env" ]; then \
		sed -i '' '/^OPENCLAW_HOOK_TOKEN=/d' $(OPENCLAW_DIR)/.env 2>/dev/null; \
		echo "  Removed OPENCLAW_HOOK_TOKEN from .env"; \
	fi
	@echo "Done."

## docker-image-setup/teardown: Deferred to future (US2 feed discovery).
## See archive/us2-future/docker/n8n-playwright.Dockerfile

manifest-update: ## M3: Update workspace file checksums in manifest.json
	@echo "Computing SHA-256 checksums for workspace files..."
	@MANIFEST='{"files":[]}'; \
	for agent_dir in $(OPENCLAW_DIR)/agents/linkedin-persona; do \
		if [ -d "$$agent_dir" ]; then \
			for f in $$agent_dir/*.md; do \
				if [ -f "$$f" ]; then \
					HASH=$$(shasum -a 256 "$$f" | awk '{print $$1}'); \
					MANIFEST=$$(echo "$$MANIFEST" | jq --arg path "$$f" --arg hash "$$HASH" \
						'.files += [{"path": $$path, "sha256": $$hash}]'); \
				fi; \
			done; \
		fi; \
	done; \
	echo "$$MANIFEST" | jq . > $(OPENCLAW_DIR)/manifest.json; \
	echo "Manifest updated: $$(echo "$$MANIFEST" | jq '.files | length') files checksummed"
	@echo "Saved to $(OPENCLAW_DIR)/manifest.json"

manifest-clean: ## M3: Remove manifest checksums file
	@rm -f $(OPENCLAW_DIR)/manifest.json && echo "Removed manifest.json" || true

workflow-export: ## M3: Export n8n workflows to workflows/ for version control
	bash $(SCRIPTS)/workflow-sync.sh export

workflow-import: ## M3: Import workflows from workflows/ into n8n
	bash $(SCRIPTS)/workflow-sync.sh import

workflow-clean: ## M3: Remove imported workflows from n8n (re-import from scratch)
	@echo "This removes all workflows from n8n. Re-import with: make workflow-import"
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || { echo "Aborted."; exit 1; }
	@docker exec -u node openclaw-n8n n8n list:workflow 2>/dev/null | while read -r line; do \
		ID=$$(echo "$$line" | awk '{print $$1}'); \
		if [ -n "$$ID" ] && [ "$$ID" != "ID" ]; then \
			docker exec -u node openclaw-n8n n8n delete:workflow --id="$$ID" 2>/dev/null; \
			echo "  Deleted workflow $$ID"; \
		fi; \
	done
	@echo "Done. Re-import: make workflow-import"

# --- Composite teardown ---

m3-teardown: ## M3: Remove ALL M3 artifacts (agents, secrets, image, manifest, workflows)
	@echo "M3 Full Teardown"
	@echo "================"
	@echo "Removes: agents, workspace files, HMAC secrets, hook config,"
	@echo "manifest, and imported workflows."
	@echo "Does NOT remove: Bun, OpenClaw, Ollama (shared tools)."
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || { echo "Aborted."; exit 1; }
	@$(MAKE) --no-print-directory workflow-clean 2>/dev/null || true
	@$(MAKE) --no-print-directory manifest-clean
	@$(MAKE) --no-print-directory hooks-teardown
	@$(MAKE) --no-print-directory hmac-teardown
	@$(MAKE) --no-print-directory agents-teardown
	@$(MAKE) --no-print-directory ollama-model-teardown
	@echo ""
	@echo "M3 teardown complete. Shared tools (Bun, OpenClaw, Ollama) left in place."

# ===========================================================================
# M4: Workspace Integrity and Host Isolation (011-workspace-integrity)
#
# Defense layers: Prevent (chflags uchg) → Contain (sandbox) →
#   Detect (startup check + monitoring) → Verify (audit)
#
# Typical flow:
#   sandbox-setup → skillallow-add → integrity-deploy → integrity-lock
#   → monitor-setup → security-tools-setup → security
# ===========================================================================

integrity-deploy: ## M4: Deploy workspace files, create signed manifest
	bash $(SCRIPTS)/integrity-deploy.sh

integrity-lock: ## M4: Set immutable flags on all protected files (requires sudo)
	sudo bash $(SCRIPTS)/integrity-lock.sh

integrity-unlock: ## M4: Unlock a specific file for editing (requires sudo, FILE=<path>)
	@if [ -z "$(FILE)" ]; then echo "Usage: make integrity-unlock FILE=<path>"; exit 1; fi
	sudo bash $(SCRIPTS)/integrity-unlock.sh --file "$(FILE)"

integrity-verify: ## M4: Run integrity check without starting agent (dry-run)
	bash $(SCRIPTS)/integrity-verify.sh --dry-run

sandbox-setup: ## M4: Configure OpenClaw sandbox mode in openclaw.json
	bash $(SCRIPTS)/sandbox-setup.sh

sandbox-teardown: ## M4: Disable sandbox mode
	bash $(SCRIPTS)/sandbox-teardown.sh

monitor-setup: ## M4: Install and start file monitoring service
	bash $(SCRIPTS)/integrity-monitor.sh --install

monitor-teardown: ## M4: Stop and remove file monitoring service
	bash $(SCRIPTS)/integrity-monitor.sh --uninstall

monitor-status: ## M4: Check monitoring service status and heartbeat
	bash $(SCRIPTS)/integrity-monitor.sh --status

container-security-config-update: ## M4: Update n8n minimum safe version (MIN_VERSION=x.y.z)
	@if [ -z "$(MIN_VERSION)" ]; then echo "Usage: make container-security-config-update MIN_VERSION=1.123.0"; exit 1; fi
	@bash -c 'source $(SCRIPTS)/lib/common.sh && source $(SCRIPTS)/lib/integrity.sh && \
		config=$$(integrity_read_container_config) && \
		config=$$(echo "$$config" | jq --arg v "$(MIN_VERSION)" ".min_n8n_version = \$$v") && \
		integrity_write_container_config "$$config" && \
		echo "Updated min_n8n_version to $(MIN_VERSION)"'

# --- Phase 3B: Security Tool Integration ---

security-tools-setup: ## M4: Install security scanning tools (Grype, docker-bench-security)
	@echo "Installing security tools..."
	@command -v grype >/dev/null 2>&1 && echo "  OK  Grype already installed ($$(grype version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1))" \
		|| (echo "  Installing Grype via Homebrew..." && brew install grype)
	@if [ -d "$(HOME)/.openclaw/tools/docker-bench-security" ]; then \
		echo "  OK  docker-bench-security already installed"; \
	else \
		echo "  Installing docker-bench-security v1.6.1..."; \
		mkdir -p "$(HOME)/.openclaw/tools"; \
		git clone --branch v1.6.1 --depth 1 --quiet \
			https://github.com/docker/docker-bench-security.git \
			"$(HOME)/.openclaw/tools/docker-bench-security"; \
		echo "  OK  docker-bench-security v1.6.1 installed"; \
	fi
	@echo ""
	@echo "Security tools installed. No teardown — shared tools."
	@echo "Manual removal: brew uninstall grype && rm -rf ~/.openclaw/tools/docker-bench-security"

security-update-hashes: ## M4: Update pinned hashes for security tools (docker-bench commit, grype binary)
	@echo "Updating security tool hashes..."
	@bash -c 'source $(SCRIPTS)/lib/common.sh && source $(SCRIPTS)/lib/integrity.sh && \
		config=$$(integrity_read_container_config) && \
		bench_hash="" && grype_hash="" && \
		if [ -d "$(HOME)/.openclaw/tools/docker-bench-security/.git" ]; then \
			bench_hash=$$(cd "$(HOME)/.openclaw/tools/docker-bench-security" && git rev-parse HEAD); \
			echo "  docker-bench commit: $${bench_hash:0:12}..."; \
		else \
			echo "  docker-bench not installed — skipping"; \
		fi && \
		if command -v grype >/dev/null 2>&1; then \
			grype_hash=$$(shasum -a 256 "$$(which grype)" | awk "{print \$$1}"); \
			echo "  grype binary hash: $${grype_hash:0:12}..."; \
		else \
			echo "  grype not installed — skipping"; \
		fi && \
		if [ -n "$$bench_hash" ]; then \
			config=$$(echo "$$config" | jq --arg h "$$bench_hash" ".pinned_bench_commit = \$$h"); \
		fi && \
		if [ -n "$$grype_hash" ]; then \
			config=$$(echo "$$config" | jq --arg h "$$grype_hash" ".pinned_grype_hash = \$$h"); \
		fi && \
		integrity_write_container_config "$$config" && \
		integrity_audit_log "security_hashes_updated" "bench=$${bench_hash:0:12},grype=$${grype_hash:0:12}" && \
		echo "Security tool hashes updated and signed."'

container-bench: ## M4: Run CIS Docker Benchmark against n8n container
	bash $(SCRIPTS)/container-bench.sh

n8n-audit: ## M4: Run n8n application security audit
	bash $(SCRIPTS)/n8n-audit.sh

scan-image: ## M4: Scan container image for CVEs (requires: brew install grype)
	bash $(SCRIPTS)/scan-image.sh

security: ## M4: Run all security layers (unified pipeline)
	bash $(SCRIPTS)/security-pipeline.sh

skillallow-add: ## M4: Add a skill to the allowlist (NAME=<skill-name>)
	@if [ -z "$(NAME)" ]; then echo "Usage: make skillallow-add NAME=<skill-name>"; exit 1; fi
	bash $(SCRIPTS)/skill-allowlist.sh add "$(NAME)"

skillallow-remove: ## M4: Remove a skill from the allowlist (NAME=<skill-name>)
	@if [ -z "$(NAME)" ]; then echo "Usage: make skillallow-remove NAME=<skill-name>"; exit 1; fi
	bash $(SCRIPTS)/skill-allowlist.sh remove "$(NAME)"

integrity-rotate-key: ## M4: Rotate HMAC signing key and re-sign all state files
	bash $(SCRIPTS)/integrity-rotate-key.sh

# ===========================================================================
# Backwards compatibility aliases (M1/M2 used verb-noun naming)
# These are silent — they don't appear in `make help`
# ===========================================================================
setup-gateway: gateway-setup
teardown-gateway: gateway-teardown
shellrc: shellrc-setup
shellrc-undo: shellrc-teardown
