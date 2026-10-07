# Basecamp

Basecamp owns the macOS development host. Foundry owns project/container runtime.
AI coding agents run on the host and are managed through mise.

| Layer | Tools | Management |
| --- | --- | --- |
| Foundation | Git, GitHub CLI (`gh`) | MacPorts |
| Foundation | Make | macOS `/usr/bin/make` |
| Foundation | mise | Official `mise.run` installer |
| Agents | Codex, OpenCode, Antigravity CLI (`agy`) | mise |
| Host tooling | Node.js LTS, bundled npm and npx | mise |
| Editor | Visual Studio Code | Official vendor distribution |
| Container Runtime | OrbStack | Official vendor distribution |
| Agent Orchestrator | Orca IDE | Official vendor distribution |

MacPorts manages Foundation CLI packages. mise manages all host-side AI coding
agents and their execution dependencies. Native macOS applications use official
vendor distributions. Project runtimes and dependencies remain inside
Foundry/project containers. Host Node.js LTS provides npm and npx for host-side
Agent and MCP tooling; project Node.js stays inside Foundry containers. npm and
npx use the versions bundled with Node.js. Orca orchestrates agents and worktrees;
mise owns agent versions.
Orca's GitHub workflows share the host Git and GitHub CLI environment.

## Setup

Install the [official MacPorts package](https://www.macports.org/install.php)
for your macOS version, including its documented Command Line Tools prerequisites.
Basecamp checks `command -v port` and fails early if MacPorts is missing; it never
installs MacPorts itself. The standard prefix is `/opt/local`.

Install these native applications in `/Applications` using the official signed
vendor distributions. On the current Intel Mac, select the macOS Intel builds:

- [Visual Studio Code](https://code.visualstudio.com/download): `Visual Studio Code.app`
- [OrbStack](https://orbstack.dev/download): `OrbStack.app`
- [Orca IDE](https://www.onorca.dev/download): `Orca.app`

Use the normal vendor updater mechanisms. Basecamp declares, documents, and
verifies applications; it does not download installers, mount DMGs, bypass
Gatekeeper, or remove quarantine attributes. Open OrbStack and complete its
first-launch setup before validation. A working alternative Docker-compatible
backend is also accepted.

```sh
export PATH="/opt/local/bin:/opt/local/sbin:$HOME/.local/bin:$PATH"
git clone <repository-url> basecamp
cd basecamp
/usr/bin/make bootstrap
```

`make bootstrap` makes this Mac satisfy the declared requirements, in order even
with `make -j`:

1. Preflight macOS, MacPorts, installer prerequisites, manifest, and link conflicts.
2. Verify active declared ports; install missing requirements with `sudo port install`.
3. Install or verify `~/.local/bin/mise` using the official installer.
4. Link global mise configuration and lockfile; install locked Agents.
5. Link dotfiles.
6. Run doctor.

Bootstrap installs missing requirements without upgrading all installed packages.
Already active declared ports are reused without invoking `sudo` during installation.
MacPorts resolves port dependencies. Run installation and update commands from an
interactive terminal so `sudo` can request administrator authentication. No package
cleanup runs automatically.
Doctor does not launch apps or select Docker contexts. Start your chosen backend
and resolve Docker environment overrides manually if validation fails.

The mise step follows the [official installer](https://mise.jdx.dev/installing-mise.html),
equivalent to `curl -fsSL https://mise.run | sh`. It downloads to a temporary file
first so download failures cannot be hidden by a pipeline. It selects
`~/.local/bin/mise` and installs only if that binary is missing. An external mise
is reported and left untouched. Invalid files or symlinks at the managed binary
path require manual resolution.

## Declared requirements

```text
Desired
├── ports.txt       # manually requested Foundation ports: git and gh
├── mise.toml       # Agent policy
└── mise.lock       # resolved Agent versions
```

`ports.txt` accepts one plain port name per line, blank lines, and full-line `#`
comments. Surrounding whitespace is ignored. Command fragments, options, variants,
and inline comments are rejected before installation. Do not list transitive
dependencies. Applications are documented requirements, not fake ports.

Normal Agent installation uses `mise install --locked`. Explicit updates use
`mise lock --global --bump` followed by locked installation, as documented in
[mise's lockfile guide](https://mise.jdx.dev/dev-tools/mise-lock.html).
Agent versions change through explicit updates; normal installation honors the lockfile.
The lockfile uses format version 3 and includes native macOS Intel and Apple
Silicon artifacts. `mise.toml` sets `AGY_CLI_DISABLE_AUTO_UPDATE = "true"` so
Antigravity CLI's [vendor self-updater](https://www.antigravity.google/docs/cli/troubleshooting/#resolve-self-updater-locks-and-failures)
cannot change the managed binary in mise environments or activated shells.
Doctor detects an Antigravity version mismatch. Restore a changed binary with
`mise install --locked --force antigravity-cli`; use `make update` for version changes.

## Shell and configuration links

```text
~/.config/mise/config.toml -> basecamp/mise.toml
~/.config/mise/mise.lock   -> basecamp/mise.lock
~/.zprofile               -> basecamp/dotfiles/zprofile
~/.zshrc                  -> basecamp/dotfiles/zshrc
~/.gitconfig              -> basecamp/dotfiles/gitconfig
```

`XDG_CONFIG_HOME`, `MISE_CONFIG_DIR`, or `MISE_GLOBAL_CONFIG_FILE` may select a
custom mise configuration location. Both global files are symlinks to the
checkout; keep it at that path.

`make link` checks every destination and reports all conflicts before creating
any links. Existing files, unrelated symlinks, and dangling symlinks cause a clear failure. Manually merge
or move conflicts; Basecamp never overwrites user files. Correct links succeed
idempotently. Put private/machine shell settings in `~/.zshrc.local`, and Git
identity or signing settings in `~/.gitconfig.local`. Merge existing local files
rather than replacing them.

The login-shell `.zprofile` prepends `/opt/local/bin`, `/opt/local/sbin`, and
`$HOME/.local/bin`, then exposes the VS Code application CLI when present.
It also loads OrbStack CLI paths and completions when the vendor shell integration
is installed.
MacPorts Git and gh should resolve to `/opt/local/bin/git` and `/opt/local/bin/gh`.
Apple Git at `/usr/bin/git` remains untouched as fallback. The interactive
`.zshrc` activates the managed mise binary and sources `.zshrc.local`; it does not
initialize MacPorts PATH. Open a new login shell after linking. Agents then work
from arbitrary project directories, without installation or upgrades at startup.
Project-local mise configuration may override global tools.

## Commands

| Command | Behavior |
| --- | --- |
| `make bootstrap` | Install requirements, link dotfiles, then doctor |
| `make install` | Preflight, install ports and mise, link global mise policy, install locked Agents |
| `make link` | Safely link global mise policy/lock and all three dotfiles |
| `make doctor` | Read-only host readiness checks |
| `make update` | Explicit Foundation and Agent updates, then doctor |
| `make macos` | Apply `macos.sh` Finder preferences and restart Finder |

Doctor groups output into Foundation, Agents, Applications, and Container Runtime.
It reports resolved CLI paths and versions and warns on functioning alternative
Foundation paths. MacPorts and the managed mise binary are required. GitHub CLI
authentication remains user-owned: run `gh auth login` separately if needed.
Basecamp never logs in or records credentials.

Agent checks validate the installed binaries and versions, not authentication or
provider account eligibility. Authenticate separately using a supported account.
Google [ended Gemini CLI access for individual/free and Google AI Pro/Ultra accounts
on June 18, 2026](https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/).
Basecamp therefore manages Antigravity CLI through mise instead of Gemini CLI.
Open a new login shell and run `agy` in your project to sign in with Google.
Authentication remains user-owned; Basecamp does not initiate sign-in or store
credentials. Antigravity CLI is independent of the Antigravity desktop app, which
is not a Basecamp requirement. See the [official CLI authentication guide](https://antigravity.google/docs/cli/install/).
The old Gemini CLI is no longer declared, and its mise installation copies were
removed during the explicit migration cleanup. Node.js is declared separately
for host npm/npx tooling. Saved credentials and sessions remain user-owned;
bootstrap and update do not perform automatic pruning or session cleanup.

Doctor checks native bundles separately from the VS Code CLI; a missing
`/usr/local/bin/code` symlink is not an error. It accepts the CLI inside the app.
Missing OrbStack is a warning if another Docker backend works. An unreachable
Docker daemon reports whether OrbStack is installed, and suggests checking its
startup and the current backend. Docker CLI, `docker info`, Compose v2 or newer,
Docker context, and a SHA-256 utility are checked. The `orbstack` context is
preferred; another functioning backend is acceptable.

`make update` runs `sudo port selfupdate`, then `sudo port upgrade` for each port
in `ports.txt`. It runs managed mise `self-update --yes --no-plugins`, refreshes
the global Agent lock, installs locked versions, and runs doctor.
Dependencies needed by declared ports may also change. Unrelated ports are not
explicit upgrade targets. No global outdated-port upgrade, inactive-port removal,
or reclaim operation runs. App updates remain vendor-owned. A failed stage stops
the workflow. Review `git diff` yourself; Basecamp never commits or pushes.

Never track GitHub authentication, agent credentials or sessions, SSH private
keys, or other secrets. Use local credential storage.

## Homebrew migration history and manual transition

This section is the sole retained Homebrew migration note. Homebrew is no longer
part of installation, PATH, or checks. Existing installations are
never automatically uninstalled.

1. Install the official MacPorts package.
2. Put `/opt/local/bin` and `/opt/local/sbin` first in PATH.
3. Install Foundation tools with `sudo port install git gh`.
4. Verify `command -v git` is `/opt/local/bin/git` and `command -v gh` is `/opt/local/bin/gh`.
5. Install/verify the managed mise binary.
6. Install/verify Codex, OpenCode, and Antigravity CLI through locked mise configuration.
7. Install the official Intel VS Code, OrbStack, and Orca applications.
8. Run `make bootstrap` and `make doctor`; resolve reported issues.
9. Only after verification, manually remove Homebrew if desired.

Merge older shell configurations and remove their obsolete package-manager PATH
setup manually before linking. Never delete `/usr/local` wholesale: it can hold
unrelated user data.

## Foundry boundary

Basecamp and Foundry remain independent repositories. Foundry owns project
language runtimes, dependencies, build/test tools, databases, and services inside
containers. Its generic host requirements remain Docker-compatible runtime,
Docker Compose v2, Git, Make, POSIX shell, and a SHA-256 utility.
Foundry does not require MacPorts, Basecamp, OrbStack specifically, Orca IDE,
Codex, OpenCode, or Antigravity CLI. Basecamp is one way to prepare a compatible host,
not a runtime dependency of Foundry. Both Makefiles should remain compatible
with macOS Make; no `gmake` dependency is introduced.
