SHELL := /bin/sh
.DEFAULT_GOAL := doctor

MISE_CONFIG_DIR ?= $(if $(XDG_CONFIG_HOME),$(XDG_CONFIG_HOME),$(HOME)/.config)/mise
MISE_GLOBAL_CONFIG_FILE ?= $(MISE_CONFIG_DIR)/config.toml
export MISE_GLOBAL_CONFIG_FILE
MISE_BIN := $(HOME)/.local/bin/mise
# Child agent installers must also resolve the independently managed mise.
export PATH := $(HOME)/.local/bin:$(PATH)
# Disable implicit cleanup and unrelated dependent repairs in every brew stage.
export HOMEBREW_NO_INSTALL_CLEANUP := 1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK := 1

.PHONY: bootstrap install link doctor update macos \
	.preflight .install-homebrew .install-mise .install-agents .link-config .prepare-runtime \
	.update-homebrew .update-mise .update-agents

# Recursive calls preserve stage ordering even with make -j.
bootstrap:
	@$(MAKE) install
	@$(MAKE) link || { printf 'Basecamp bootstrap failed during dotfile linking.\n' >&2; exit 1; }
	@$(MAKE) .prepare-runtime || { printf 'Basecamp bootstrap failed during container runtime preparation.\n' >&2; exit 1; }
	@$(MAKE) doctor || { printf 'Basecamp bootstrap failed during validation.\n' >&2; exit 1; }

install:
	@$(MAKE) .preflight || { printf 'Basecamp bootstrap failed during preflight.\n' >&2; exit 1; }
	@$(MAKE) .install-homebrew || { printf 'Basecamp bootstrap failed during Homebrew installation.\n' >&2; exit 1; }
	@$(MAKE) .install-mise || { printf 'Basecamp bootstrap failed during mise installation.\n' >&2; exit 1; }
	@$(MAKE) .install-agents || { printf 'Basecamp bootstrap failed during Agent installation.\n' >&2; exit 1; }

.preflight:
	@printf '==> Preflight\n'
	@set -eu; \
	[ "$$(uname -s)" = Darwin ] || { printf 'error: Basecamp requires macOS.\n' >&2; exit 1; }; \
	for tool in brew git make curl; do \
		command -v "$$tool" >/dev/null 2>&1 || { printf 'error: required prerequisite missing: %s\n' "$$tool" >&2; exit 1; }; \
	done; \
	if [ -e "$(MISE_BIN)" ] || [ -L "$(MISE_BIN)" ]; then \
		if [ -L "$(MISE_BIN)" ] || [ ! -f "$(MISE_BIN)" ] || [ ! -x "$(MISE_BIN)" ]; then \
			printf 'error: %s is not a regular executable. Resolve it manually; Basecamp will not replace it.\n' "$(MISE_BIN)" >&2; exit 1; \
		fi; \
	elif other=$$(command -v mise 2>/dev/null); then \
		printf 'warn Existing mise at %s remains untouched; Basecamp manages %s.\n' "$$other" "$(MISE_BIN)"; \
	fi
	@$(MAKE) .link-config CHECK_ONLY=1 WITH_DOTFILES=1

.install-homebrew:
	@printf '==> Homebrew (install missing requirements)\n'
	@export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_UPGRADE=1; \
	if ! brew bundle install --no-upgrade --file="$(CURDIR)/Brewfile"; then \
		printf '\nDeclared Homebrew requirements still unsatisfied:\n' >&2; \
		brew bundle check --no-upgrade --verbose --file="$(CURDIR)/Brewfile" || true; \
		exit 1; \
	fi

.install-mise:
	@printf '==> mise (official binary)\n'
	@set -eu; \
	if [ ! -x "$(MISE_BIN)" ]; then \
		installer=$$(mktemp); \
		trap 'rm -f "$$installer"' 0; trap 'exit 1' 1 2 3 15; \
		curl -fsSL https://mise.run -o "$$installer"; \
		MISE_INSTALL_PATH="$(MISE_BIN)" sh "$$installer"; \
	fi; \
	"$(MISE_BIN)" --version

.install-agents:
	@printf '==> Agents (locked mise tools)\n'
	@$(MAKE) .link-config
	@"$(MISE_BIN)" trust "$(CURDIR)/mise.toml"
	@"$(MISE_BIN)" install --locked

link:
	@printf '==> Dotfiles and global mise links\n'
	@$(MAKE) .link-config WITH_DOTFILES=1

# One internal recipe shares the preflight and linking safety checks.
.link-config:
	@set -eu; \
	set -- "$(CURDIR)/mise.toml" "$$MISE_GLOBAL_CONFIG_FILE" \
		"$(CURDIR)/mise.lock" "$$(dirname "$$MISE_GLOBAL_CONFIG_FILE")/mise.lock"; \
	if [ "$${WITH_DOTFILES:-0}" = 1 ]; then \
		set -- "$$@" "$(CURDIR)/dotfiles/zshrc" "$$HOME/.zshrc" \
			"$(CURDIR)/dotfiles/gitconfig" "$$HOME/.gitconfig"; \
	fi; \
	check_links() { \
		while [ "$$#" -gt 0 ]; do \
			source=$$1; destination=$$2; shift 2; \
			[ -f "$$source" ] || { printf 'error: required tracked file missing: %s\n' "$$source" >&2; exit 1; }; \
			if [ -L "$$destination" ] && [ "$$(readlink "$$destination")" = "$$source" ]; then continue; fi; \
			if [ -e "$$destination" ] || [ -L "$$destination" ]; then \
				printf 'error: %s already exists and is not the Basecamp symlink.\n' "$$destination" >&2; \
				case "$$destination" in \
					"$$HOME/.zshrc") printf 'Preserve machine settings in ~/.zshrc.local, then manually move the original ~/.zshrc before retrying.\n' >&2;; \
					"$$HOME/.gitconfig") printf 'Preserve Git settings in ~/.gitconfig.local, then manually move the original ~/.gitconfig before retrying.\n' >&2;; \
					*) printf 'Manually merge or move the conflicting configuration, then retry.\n' >&2;; \
				esac; \
				exit 1; \
			fi; \
		done; \
	}; \
	check_links "$$@"; \
	[ "$${CHECK_ONLY:-0}" != 1 ] || exit 0; \
	while [ "$$#" -gt 0 ]; do \
		source=$$1; destination=$$2; shift 2; \
		if [ ! -L "$$destination" ]; then \
			mkdir -p "$$(dirname "$$destination")"; \
			ln -s "$$source" "$$destination"; \
		fi; \
		printf 'ok   %s\n' "$$destination"; \
	done

# Startup is a bootstrap dependency; doctor remains a read-only readiness check.
.prepare-runtime:
	@printf '==> Container runtime preparation\n'
	@set -eu; \
	if docker info >/dev/null 2>&1; then \
		printf 'ok   Active Docker backend is ready\n'; exit 0; \
	fi; \
	if [ -n "$${DOCKER_HOST:-}" ] || { [ -n "$${DOCKER_CONTEXT:-}" ] && [ "$$DOCKER_CONTEXT" != orbstack ]; }; then \
		printf 'error: Docker environment override is unreachable. Start that backend or unset DOCKER_HOST/DOCKER_CONTEXT before using OrbStack.\n' >&2; exit 1; \
	fi; \
	app='/Applications/OrbStack.app'; \
	if [ ! -d "$$app" ]; then app="$$HOME/Applications/OrbStack.app"; fi; \
	[ -d "$$app" ] || { printf 'error: No ready Docker backend and OrbStack.app is missing.\n' >&2; exit 1; }; \
	open -a "$$app"; \
	printf 'Complete any first-launch setup in OrbStack. Waiting for Docker (60 checks, 2-second intervals)...\n'; \
	attempt=0; \
	while [ "$$attempt" -lt 60 ]; do \
		if docker --context orbstack info >/dev/null 2>&1; then \
			docker context use orbstack; \
			printf 'ok   OrbStack Docker backend is ready\n'; exit 0; \
		fi; \
		attempt=$$((attempt + 1)); \
		if [ "$$attempt" -lt 60 ]; then sleep 2; fi; \
	done; \
	printf 'error: OrbStack Docker backend is not ready. Complete its setup or resolve its startup error, then rerun make bootstrap.\n' >&2; \
	exit 1

doctor:
	@status=0; \
	check() { \
		label=$$1; shift; \
		if "$$@" >/dev/null 2>&1; then printf 'ok   %s\n' "$$label"; \
		else printf 'fail %s\n' "$$label"; status=1; fi; \
	}; \
	printf '[Foundation]\n'; \
	for tool in brew git make; do check "$$tool" command -v "$$tool"; done; \
	check mise "$(MISE_BIN)" --version; \
	clt=$$(HOMEBREW_NO_AUTO_UPDATE=1 brew doctor check_clt_up_to_date 2>&1) || true; \
	case "$$clt" in *'A newer Command Line Tools release is available.'*) \
		printf 'warn A newer Command Line Tools release is available. Update through macOS Software Update.\n';; esac; \
	if [ -L "$$MISE_GLOBAL_CONFIG_FILE" ] && [ "$$(readlink "$$MISE_GLOBAL_CONFIG_FILE")" = "$(CURDIR)/mise.toml" ]; then \
		printf 'ok   mise global config\n'; \
	else printf 'fail mise global config (run make link)\n'; status=1; fi; \
	global_lock="$$(dirname "$$MISE_GLOBAL_CONFIG_FILE")/mise.lock"; \
	if [ -L "$$global_lock" ] && [ "$$(readlink "$$global_lock")" = "$(CURDIR)/mise.lock" ]; then \
		printf 'ok   mise global lockfile\n'; \
	else printf 'fail mise global lockfile (run make link)\n'; status=1; fi; \
	printf '\n[Agents — mise]\n'; \
	for tool in codex opencode gemini; do check "$$tool" "$(MISE_BIN)" which "$$tool"; done; \
	printf '\n[Applications]\n'; \
	if command -v code >/dev/null 2>&1; then printf 'ok   VS Code CLI\n'; \
	elif [ -d '/Applications/Visual Studio Code.app' ] || [ -d "$$HOME/Applications/Visual Studio Code.app" ]; then \
		printf 'warn VS Code installed; expose code using its Install code command in PATH action.\n'; \
	else printf 'fail Visual Studio Code\n'; status=1; fi; \
	if [ -d '/Applications/OrbStack.app' ] || [ -d "$$HOME/Applications/OrbStack.app" ]; then \
		printf 'ok   OrbStack\n'; \
	else printf 'warn OrbStack is not installed; a working alternative Docker backend is accepted.\n'; fi; \
	if [ -d '/Applications/Orca.app' ] || [ -d "$$HOME/Applications/Orca.app" ]; then \
		printf 'ok   Orca IDE\n'; \
	else printf 'fail Orca IDE (Orca.app missing)\n'; status=1; fi; \
	printf '\n[Container Runtime]\n'; \
	check docker command -v docker; \
	check 'Docker daemon' docker info; \
	if version=$$(docker compose version --short 2>/dev/null); then \
		version=$${version#v}; major=$${version%%.*}; \
		if [ "$$major" -ge 2 ] 2>/dev/null; then printf 'ok   Docker Compose v2+\n'; \
		else printf 'fail Docker Compose v2+ (found %s)\n' "$$version"; status=1; fi; \
	else printf 'fail Docker Compose v2+\n'; status=1; fi; \
	if command -v sha256sum >/dev/null 2>&1; then printf 'ok   sha256sum\n'; \
	elif command -v shasum >/dev/null 2>&1; then printf 'ok   shasum\n'; \
	else printf 'fail SHA-256 tooling (sha256sum or shasum)\n'; status=1; fi; \
	if context=$$(docker context show 2>/dev/null) && [ -n "$$context" ]; then \
		printf 'ok   Docker context: %s\n' "$$context"; \
		if [ "$$context" != orbstack ]; then printf 'warn OrbStack is the recommended Basecamp runtime.\n'; fi; \
	else printf 'fail Docker context\n'; status=1; fi; \
	if [ "$$status" -eq 0 ]; then printf '\nHost is ready.\n'; \
	else printf '\nHost needs attention.\n'; fi; \
	exit "$$status"

update:
	@$(MAKE) .preflight || { printf 'Basecamp update failed during preflight.\n' >&2; exit 1; }
	@test -x "$(MISE_BIN)" || { printf 'error: managed mise is missing; run make bootstrap first.\n' >&2; exit 1; }
	@$(MAKE) .link-config
	@$(MAKE) .update-homebrew || { printf 'Basecamp update failed during Homebrew update.\n' >&2; exit 1; }
	@$(MAKE) .update-mise || { printf 'Basecamp update failed during mise self-update.\n' >&2; exit 1; }
	@$(MAKE) .update-agents || { printf 'Basecamp update failed during Agent update.\n' >&2; exit 1; }
	@$(MAKE) doctor || { printf 'Basecamp update failed during validation.\n' >&2; exit 1; }
	@printf '\nReview changes with: git diff\n'

.update-homebrew:
	@printf '==> Homebrew (update declared requirements)\n'
	@brew update
	@HOMEBREW_UPGRADE_GREEDY=1 brew bundle install --upgrade --file="$(CURDIR)/Brewfile"

.update-mise:
	@printf '==> mise self-update\n'
	@"$(MISE_BIN)" self-update --yes --no-plugins

.update-agents:
	@printf '==> Agents (refresh global lockfile)\n'
	@"$(MISE_BIN)" lock --global --bump
	@"$(MISE_BIN)" install --locked

macos:
	/bin/sh "$(CURDIR)/macos.sh"
