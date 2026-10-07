SHELL := /bin/sh
.DEFAULT_GOAL := doctor

MISE_CONFIG_DIR ?= $(if $(XDG_CONFIG_HOME),$(XDG_CONFIG_HOME),$(HOME)/.config)/mise
MISE_GLOBAL_CONFIG_FILE ?= $(MISE_CONFIG_DIR)/config.toml
export MISE_GLOBAL_CONFIG_FILE
MISE_BIN := $(HOME)/.local/bin/mise
# Foundation precedes mise, native application CLIs, and inherited system paths.
export PATH := /opt/local/bin:/opt/local/sbin:$(HOME)/.local/bin:/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$(PATH)
# Recursive stages use macOS Make, regardless of another make on PATH.
MAKE := /usr/bin/make
export LC_ALL := C

.PHONY: bootstrap install link doctor update macos \
	.preflight .install-ports .install-mise .install-agents .link-config .ports \
	.update-ports .update-mise .update-agents

# Recursive calls preserve stage ordering even with make -j.
bootstrap:
	@$(MAKE) install
	@$(MAKE) link || { printf 'Basecamp bootstrap failed during dotfile linking.\n' >&2; exit 1; }
	@$(MAKE) doctor || { printf 'Basecamp bootstrap failed during validation.\n' >&2; exit 1; }

install:
	@$(MAKE) .preflight || { printf 'Basecamp bootstrap failed during preflight.\n' >&2; exit 1; }
	@$(MAKE) .install-ports || { printf 'Basecamp bootstrap failed during MacPorts installation.\n' >&2; exit 1; }
	@$(MAKE) .install-mise || { printf 'Basecamp bootstrap failed during mise installation.\n' >&2; exit 1; }
	@$(MAKE) .install-agents || { printf 'Basecamp bootstrap failed during Agent installation.\n' >&2; exit 1; }

.preflight:
	@printf '==> Preflight\n'
	@set -eu; \
	[ "$$(uname -s)" = Darwin ] || { printf 'error: Basecamp requires macOS.\n' >&2; exit 1; }; \
	command -v port >/dev/null 2>&1 || { printf 'MacPorts is required.\n\nInstall the official package for your macOS version:\nhttps://www.macports.org/install.php\n' >&2; exit 1; }; \
	[ -x /usr/bin/make ] || { printf 'error: macOS Make is missing.\n' >&2; exit 1; }; \
	for tool in curl sudo; do \
		command -v "$$tool" >/dev/null 2>&1 || { printf 'error: required prerequisite missing: %s\n' "$$tool" >&2; exit 1; }; \
	done; \
	if [ -e "$(MISE_BIN)" ] || [ -L "$(MISE_BIN)" ]; then \
		if [ -L "$(MISE_BIN)" ] || [ ! -f "$(MISE_BIN)" ] || [ ! -x "$(MISE_BIN)" ]; then \
			printf 'error: %s is not a regular executable. Resolve it manually; Basecamp will not replace it.\n' "$(MISE_BIN)" >&2; exit 1; \
		fi; \
	elif other=$$(command -v mise 2>/dev/null); then \
		printf 'warn Existing mise at %s remains untouched; Basecamp manages %s.\n' "$$other" "$(MISE_BIN)"; \
	fi
	@$(MAKE) .ports CHECK_ONLY=1
	@$(MAKE) .link-config CHECK_ONLY=1 WITH_DOTFILES=1

.install-ports:
	@printf '==> MacPorts (install declared requirements)\n'
	@$(MAKE) .ports PORT_ACTION=install

# Validate the whole manifest before invoking sudo. Only plain port names are accepted.
.ports:
	@set -eu; \
	manifest=$$(mktemp); \
	trap 'rm -f "$$manifest"' 0; trap 'exit 1' 1 2 3 15; \
	awk '{ sub(/^[ \t]+/, ""); sub(/[ \t]+$$/, "") } \
		/^$$/ || /^#/ { next } \
		!/^[a-z0-9][a-z0-9_.-]*$$/ { printf "error: ports.txt:%d: expected one plain port name\n", NR > "/dev/stderr"; exit 1 } \
		{ print }' "$(CURDIR)/ports.txt" > "$$manifest"; \
	[ "$${CHECK_ONLY:-0}" != 1 ] || exit 0; \
	case "$${PORT_ACTION:-}" in install|upgrade) ;; *) printf 'error: invalid port action\n' >&2; exit 1;; esac; \
	while IFS= read -r port_name; do \
		if [ "$$PORT_ACTION" = install ] && installed=$$(port -q installed "$$port_name" 2>/dev/null) && \
			printf '%s\n' "$$installed" | awk -v name="$$port_name" '$$1 == name && $$3 == "(active)" { found=1 } END { exit !found }'; then \
			printf 'ok   %s (already active)\n' "$$port_name"; continue; \
		fi; \
		sudo port "$$PORT_ACTION" "$$port_name" || { \
			printf 'error: MacPorts %s failed for %s. Run make from an interactive terminal with administrator access; see the port error above.\n' "$$PORT_ACTION" "$$port_name" >&2; exit 1; \
		}; \
	done < "$$manifest"

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
		set -- "$$@" "$(CURDIR)/dotfiles/zprofile" "$$HOME/.zprofile" \
			"$(CURDIR)/dotfiles/zshrc" "$$HOME/.zshrc" \
			"$(CURDIR)/dotfiles/gitconfig" "$$HOME/.gitconfig"; \
	fi; \
	check_links() { \
		failures=0; \
		while [ "$$#" -gt 0 ]; do \
			source=$$1; destination=$$2; shift 2; \
			[ -f "$$source" ] || { printf 'error: required tracked file missing: %s\n' "$$source" >&2; failures=1; continue; }; \
			if [ -L "$$destination" ] && [ "$$(readlink "$$destination")" = "$$source" ]; then continue; fi; \
			if [ -e "$$destination" ] || [ -L "$$destination" ]; then \
				printf 'error: %s already exists and is not the Basecamp symlink.\n' "$$destination" >&2; \
				case "$$destination" in \
					"$$HOME/.zshrc") printf 'Preserve machine settings in ~/.zshrc.local, then manually move the original ~/.zshrc before retrying.\n' >&2;; \
					"$$HOME/.gitconfig") printf 'Preserve Git settings in ~/.gitconfig.local, then manually move the original ~/.gitconfig before retrying.\n' >&2;; \
					*) printf 'Manually merge or move the conflicting configuration, then retry.\n' >&2;; \
				esac; \
				failures=1; \
			fi; \
		done; \
		[ "$$failures" -eq 0 ]; \
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

update:
	@$(MAKE) .preflight || { printf 'Basecamp update failed during preflight.\n' >&2; exit 1; }
	@test -x "$(MISE_BIN)" || { printf 'error: managed mise is missing; run make bootstrap first.\n' >&2; exit 1; }
	@$(MAKE) .link-config
	@$(MAKE) .update-ports || { printf 'Basecamp update failed during MacPorts update.\n' >&2; exit 1; }
	@$(MAKE) .update-mise || { printf 'Basecamp update failed during mise self-update.\n' >&2; exit 1; }
	@$(MAKE) .update-agents || { printf 'Basecamp update failed during Agent update.\n' >&2; exit 1; }
	@$(MAKE) doctor || { printf 'Basecamp update failed during validation.\n' >&2; exit 1; }
	@printf '\nReview changes with: git diff\n'

.update-ports:
	@printf '==> MacPorts (update declared requirements)\n'
	@sudo port selfupdate || { printf 'error: MacPorts selfupdate failed. Run make update from an interactive terminal with administrator access; see the port error above.\n' >&2; exit 1; }
	@$(MAKE) .ports PORT_ACTION=upgrade

.update-mise:
	@printf '==> mise self-update\n'
	@"$(MISE_BIN)" self-update --yes --no-plugins

.update-agents:
	@printf '==> Agents (refresh global lockfile)\n'
	@"$(MISE_BIN)" lock --global --bump
	@"$(MISE_BIN)" install --locked

macos:
	/bin/sh "$(CURDIR)/macos.sh"

# Read-only checks; never start applications, change contexts, or authenticate.
doctor:
	@status=0; export MISE_AUTO_INSTALL=0 MISE_EXEC_AUTO_INSTALL=0; \
	check_tool() { \
		label=$$1; tool=$$2; expected=$$3; \
		version_arg=--version; if [ "$$tool" = port ]; then version_arg=version; fi; \
		if path=$$(command -v "$$tool" 2>/dev/null) && version=$$("$$path" "$$version_arg" 2>/dev/null); then \
			printf 'ok   %-16s %s (%s)\n' "$$label" "$$path" "$$(printf '%s\n' "$$version" | head -n 1)"; \
			if [ "$$path" != "$$expected" ]; then printf 'warn %s resolves to %s; Basecamp expects %s\n' "$$label" "$$path" "$$expected"; fi; \
		else printf 'fail %s (missing or unusable)\n' "$$label"; status=1; fi; \
	}; \
	printf 'Foundation\n'; \
	check_tool MacPorts port /opt/local/bin/port; \
	check_tool Git git /opt/local/bin/git; \
	check_tool 'GitHub CLI' gh /opt/local/bin/gh; \
	check_tool Make make /usr/bin/make; \
	if version=$$("$(MISE_BIN)" --version 2>/dev/null); then \
		printf 'ok   %-16s %s (%s)\n' mise "$(MISE_BIN)" "$$version"; \
		path=$$(command -v mise 2>/dev/null) || path=missing; \
		if [ "$$path" != "$(MISE_BIN)" ]; then printf 'warn mise resolves to %s; Basecamp uses %s\n' "$$path" "$(MISE_BIN)"; fi; \
	else printf 'fail mise (run make install)\n'; status=1; fi; \
	for pair in config lock; do \
		case "$$pair" in config) source="$(CURDIR)/mise.toml"; destination="$$MISE_GLOBAL_CONFIG_FILE";; \
			lock) source="$(CURDIR)/mise.lock"; destination="$$(dirname "$$MISE_GLOBAL_CONFIG_FILE")/mise.lock";; esac; \
		if [ -L "$$destination" ] && [ "$$(readlink "$$destination")" = "$$source" ]; then printf 'ok   mise global %s\n' "$$pair"; \
		else printf 'fail mise global %s (run make link)\n' "$$pair"; status=1; fi; \
	done; \
	printf '\nAgents\n'; \
	for tool in codex opencode agy node npm npx; do \
		if path=$$("$(MISE_BIN)" which "$$tool" 2>/dev/null) && version=$$("$(MISE_BIN)" exec --locked --no-deps -- "$$path" --version 2>/dev/null); then \
			if [ "$$tool" = agy ]; then \
				expected=$$("$(MISE_BIN)" current antigravity-cli 2>/dev/null) || expected=unknown; \
				if [ "$$version" != "$$expected" ]; then \
					printf 'fail agy reports %s; mise expects %s. Restore with mise install --locked --force antigravity-cli.\n' "$$version" "$$expected"; status=1; continue; \
				fi; \
			fi; \
			printf 'ok   %-16s %s (%s)\n' "$$tool" "$$path" "$$(printf '%s\n' "$$version" | head -n 1)"; \
		else printf 'fail %s (locked mise tool missing or unusable)\n' "$$tool"; status=1; fi; \
	done; \
	printf '\nApplications\n'; \
	for app in 'Visual Studio Code' OrbStack Orca; do \
		if [ -d "/Applications/$$app.app" ]; then printf 'ok   %s /Applications/%s.app\n' "$$app" "$$app"; \
		elif [ "$$app" = OrbStack ]; then printf 'warn OrbStack not installed; a functioning alternative Docker backend is accepted.\n'; \
		else printf 'fail %s (/Applications/%s.app missing; install the official vendor build)\n' "$$app" "$$app"; status=1; fi; \
	done; \
	if path=$$(command -v code 2>/dev/null); then printf 'ok   VS Code CLI %s\n' "$$path"; \
	elif [ -x '/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code' ]; then \
		printf 'ok   VS Code CLI /Applications/Visual Studio Code.app/Contents/Resources/app/bin/code\n'; \
	else printf 'warn VS Code CLI unavailable; verify the vendor application and open a new login shell.\n'; fi; \
	printf '\nContainer Runtime\n'; \
	check_tool Docker docker "$$(command -v docker 2>/dev/null || true)"; \
	if docker info >/dev/null 2>&1; then printf 'ok   Docker daemon\n'; \
	else \
		if [ -d /Applications/OrbStack.app ]; then printf 'fail Docker daemon (OrbStack installed but not running or current backend unreachable; open OrbStack and check Docker context/overrides)\n'; \
		else printf 'fail Docker daemon (OrbStack not installed; install/start a Docker-compatible runtime)\n'; fi; status=1; \
	fi; \
	if version=$$(docker compose version --short 2>/dev/null); then \
		version=$${version#v}; major=$${version%%.*}; \
		if [ "$$major" -ge 2 ] 2>/dev/null; then printf 'ok   Docker Compose v2+ %s\n' "$$version"; \
		else printf 'fail Docker Compose v2+ (found %s)\n' "$$version"; status=1; fi; \
	else printf 'fail Docker Compose v2+\n'; status=1; fi; \
	if context=$$(docker context show 2>/dev/null) && [ -n "$$context" ]; then \
		printf 'ok   context: %s\n' "$$context"; \
		if [ "$$context" != orbstack ]; then printf 'warn OrbStack context is preferred; a working alternative is accepted.\n'; fi; \
	else printf 'fail Docker context\n'; status=1; fi; \
	if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then printf 'ok   SHA-256 utility\n'; \
	else printf 'fail SHA-256 utility\n'; status=1; fi; \
	printf '\ninfo Agent checks verify installation; account authentication and provider eligibility are user-managed.\n'; \
	if [ "$$status" -eq 0 ]; then printf '\nHost is ready.\n'; else printf '\nHost needs attention.\n'; fi; \
	exit "$$status"
