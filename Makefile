# OpenClaw — macOS hardening toolkit
# Usage: make install | make uninstall | make verify | make audit

SHELL := /bin/bash
SCRIPTS := scripts
COMPOSE := $(SCRIPTS)/templates/docker-compose.yml
PREFIX := /opt/n8n
OPENCLAW_DIR := $(HOME)/.openclaw

.PHONY: install setup-gateway audit audit-save fix fix-auto verify uninstall shellrc help

help: ## Show available targets
	@grep -E '^[a-z_-]+:.*##' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

install: ## Prepare macOS: install tools, create directories, deploy scripts
	bash $(SCRIPTS)/bootstrap.sh

setup-gateway: ## Start Colima, deploy n8n container, configure secrets
	bash $(SCRIPTS)/gateway-setup.sh

audit: ## Run security audit (requires sudo)
	sudo bash $(SCRIPTS)/hardening-audit.sh

audit-save: ## Save audit results as JSON for the fix script (requires sudo)
	@sudo bash $(SCRIPTS)/hardening-audit.sh --json | sudo tee $(PREFIX)/logs/audit/audit-$$(date +%Y%m%d-%H%M%S).json > /dev/null
	@echo "Audit saved to $(PREFIX)/logs/audit/"

fix: ## Apply hardening fixes interactively (requires sudo)
	sudo bash $(SCRIPTS)/hardening-fix.sh --interactive

fix-auto: ## Apply safe hardening fixes without prompts (requires sudo)
	sudo bash $(SCRIPTS)/hardening-fix.sh --auto

shellrc: ## Set up openclaw aliases in ~/.openclaw/shellrc
	@mkdir -p $(OPENCLAW_DIR)
	@REPO_ROOT="$$(cd "$$(dirname "$(MAKEFILE_LIST)")" && pwd)"; \
	printf '# OpenClaw Shell Configuration\n# Source: %s/Makefile shellrc target\n\nalias openclaw-audit='\''sudo bash %s/scripts/hardening-audit.sh'\''\nalias openclaw-fix='\''sudo bash %s/scripts/hardening-fix.sh --interactive'\''\nalias n8n-token='\''security find-generic-password -a "openclaw" -s "n8n-gateway-bearer" -w'\''\n' \
		"$$REPO_ROOT" "$$REPO_ROOT" "$$REPO_ROOT" > $(OPENCLAW_DIR)/shellrc
	@RC_FILE="$$( [[ "$$(basename "$$SHELL")" == "bash" ]] && echo "$$HOME/.bash_profile" || echo "$$HOME/.zshrc" )"; \
	grep -qF 'openclaw/shellrc' "$$RC_FILE" 2>/dev/null || \
		printf '\n[ -f ~/.openclaw/shellrc ] && source ~/.openclaw/shellrc\n' >> "$$RC_FILE"; \
	echo "Aliases installed. Run: source $$RC_FILE"

verify: ## Check that all expected artifacts are present
	@echo "OpenClaw Verify"
	@echo "==============="
	@brew bundle check --file=Brewfile 2>/dev/null && echo "  OK  Brew packages" || echo "  MISSING  Some brew packages (run: make install)"
	@for f in hardening-audit.sh hardening-fix.sh audit-notify.sh audit-cron.sh; do \
		[ -f "$(PREFIX)/scripts/$$f" ] && printf "  OK  %s\n" "$(PREFIX)/scripts/$$f" || printf "  MISSING  %s\n" "$(PREFIX)/scripts/$$f"; \
	done
	@sudo test -f "$(PREFIX)/etc/notify.conf" && echo "  OK  $(PREFIX)/etc/notify.conf" || echo "  MISSING  notify.conf"
	@[ -d "$(PREFIX)" ] && echo "  OK  $(PREFIX)/ exists" || echo "  MISSING  $(PREFIX)/"
	@colima status 2>/dev/null && echo "  OK  Colima running" || echo "  DOWN  Colima not running"
	@docker ps 2>/dev/null | grep -q n8n && echo "  OK  n8n container running" || echo "  DOWN  n8n container not running"
	@[ -f "$(OPENCLAW_DIR)/shellrc" ] && echo "  OK  Shell aliases" || echo "  MISSING  Shell aliases (run: make shellrc)"

uninstall: ## Remove all openclaw artifacts (keeps hardening — use restore script)
	@echo "OpenClaw Uninstall"
	@echo "=================="
	@echo ""
	@echo "This will remove openclaw tooling. Hardening changes are NOT reversed."
	@echo "To reverse hardening: run the restore script from your last 'make fix' run."
	@echo ""
	@read -p "Continue? [y/N] " confirm && [ "$$confirm" = "y" ] || { echo "Aborted."; exit 1; }
	@echo ""
	-docker compose -f $(COMPOSE) down -v 2>/dev/null
	@echo "  Removed Docker containers and volumes"
	-colima stop 2>/dev/null
	-colima delete --force 2>/dev/null
	@echo "  Removed Colima VM"
	-sudo launchctl bootout system/com.openclaw.audit-cron 2>/dev/null
	-sudo rm -f /Library/LaunchDaemons/com.openclaw.audit-cron.plist
	@echo "  Removed launchd plist"
	-security delete-generic-password -s n8n-gateway-bearer 2>/dev/null
	@echo "  Removed keychain entry"
	-sudo rm -rf $(PREFIX)
	@echo "  Removed $(PREFIX)/"
	-rm -f $(OPENCLAW_DIR)/shellrc
	-sed -i '' '/openclaw\/shellrc/d' ~/.zshrc ~/.bash_profile 2>/dev/null
	@echo "  Removed shell aliases"
	@echo ""
	@echo "Done. Brew packages left in place (remove manually: brew bundle cleanup --file=Brewfile --force)"
	@echo "Hardening restore scripts: ls /opt/n8n/logs/audit/pre-fix-restore-*.sh 2>/dev/null || echo 'none found'"
