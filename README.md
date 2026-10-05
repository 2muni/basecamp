# Basecamp

Reproducible macOS host environment for development tools, container runtimes,
shell configuration, and AI coding agents.

## Ownership

| Layer | Tools | Management |
| --- | --- | --- |
| Foundation | Git, GNU Make | Homebrew |
| Foundation | mise | Official single-binary installer (`mise.run`) |
| Agents | Codex, OpenCode, Gemini CLI | mise |
| Editor | Visual Studio Code | Homebrew |
| Container Runtime | OrbStack | Homebrew |
| Agent Orchestrator | Orca IDE | Homebrew (`stablyai/orca` tap) |

mise installs and versions all agents; Orca orchestrates them. VS Code is an
editor. Neither GUI application owns agent installation or project runtimes.
Extensions are not synchronized. Node.js is installed through mise solely to
execute host-side Gemini CLI; project Node.js remains inside project containers.

`Brewfile` defines required native host infrastructure and applications.
`mise.toml` defines host-side Agent policy; version-controlled `mise.lock` fixes
the resolved Agent versions. mise's installer is part of bootstrap infrastructure.
Basecamp defines development prerequisites, without inventorying the rest of the
workstation. Homebrew packages and the mise manager binary are not version-locked.

## Setup

Start with macOS, Homebrew, Git, Make, and curl available. Basecamp does not
bootstrap Homebrew. Apple's Make can run bootstrap; Homebrew GNU Make supplies
an explicit modern implementation. The linked zshrc adds its `gnubin` directory
to PATH ([Homebrew Make details](https://formulae.brew.sh/formula/make.html)).

```sh
git clone <repository-url> basecamp
cd basecamp
make bootstrap
```

Bootstrap installs missing requirements, in this order even with `make -j`:

1. Preflight prerequisites, managed binary path, and all configuration conflicts.
2. `brew bundle install --no-upgrade --file=.../Brewfile`.
3. Install the official mise binary at `~/.local/bin/mise` only if missing.
4. Link global mise policy and lockfile, then install agents with `--locked`.
5. Link dotfiles.
6. Prepare a functioning Docker backend, then run doctor.

Runtime preparation accepts the active Docker backend if it is already working.
Otherwise bootstrap opens OrbStack and waits for its Docker engine before selecting
the `orbstack` context. Complete any first-launch prompts in the app while bootstrap
waits (60 readiness checks, two seconds apart). Context selection happens only after
the engine responds. Unreachable explicit `DOCKER_HOST` or `DOCKER_CONTEXT` overrides
require manual resolution; bootstrap does not silently replace them. Startup or
setup failure stops at runtime preparation, before doctor. It does not reset or
migrate Docker data.

Bootstrap never runs an explicit package upgrade. Its Homebrew stage disables
automatic metadata updates, installation upgrades, dependent repairs, and
cleanup. Missing packages may still require their own dependencies or a source
build if Homebrew offers no compatible bottle; mise itself uses official
prebuilt binaries on both Intel and Apple Silicon, avoiding Homebrew's compiler
build chain.

The mise step uses the [official installer](https://mise.jdx.dev/installing-mise.html),
equivalent to `curl -fsSL https://mise.run | sh`. Basecamp downloads it to a
temporary file before running it so a failed download cannot be hidden by a
successful shell pipeline. It explicitly selects `~/.local/bin/mise`, verifies
its version, and reuses an existing executable there without reinstalling it.
An external mise on PATH is reported before installation and left untouched;
it is not automatically uninstalled or upgraded. Invalid files or symlinks at
the managed binary path cause preflight to fail for manual resolution.

Every installation failure identifies its stage: preflight, Homebrew, mise,
Agents, dotfiles, or validation. A Homebrew failure triggers only this diagnostic:

```sh
brew bundle check --no-upgrade --verbose --file=./Brewfile
```

Its output identifies requirements still missing; a failed Bundle transaction
alone does not establish that every listed app is broken. There are no automatic
retries, package repairs, removals, or Command Line Tools reinstalls.

## Global configuration and validation

Safe symlinks keep the repository authoritative:

```text
~/.config/mise/config.toml -> basecamp/mise.toml
~/.config/mise/mise.lock   -> basecamp/mise.lock
~/.zshrc                  -> basecamp/dotfiles/zshrc
~/.gitconfig              -> basecamp/dotfiles/gitconfig
```

The config and lock are one logical pair; the global lock is never an independent
copy. `XDG_CONFIG_HOME`, `MISE_CONFIG_DIR`, or `MISE_GLOBAL_CONFIG_FILE` can select
a custom location. Existing unrelated files or symlinks, including dangling
links, are never overwritten. Manually merge or remove conflicts before retrying.
Correct links are accepted on repeated runs; keep the checkout at its linked path.
For an existing `~/.zshrc` or `~/.gitconfig`, preserve its local settings in
`~/.zshrc.local` or `~/.gitconfig.local` and manually move the original file before
retrying. If a local file already exists, merge rather than overwrite it. Preflight
checks these conflicts before any package installation.
If an earlier zshrc exported `MISE_GLOBAL_CONFIG_FILE` to the repository itself,
remove that export and unset the variable before bootstrap.

Open a new shell to activate `~/.local/bin/mise` directly. Agents are available
from arbitrary directories; shell startup neither installs nor upgrades them.
Project-local mise settings can override global selections. Bootstrap prepares
the container runtime before validation. For subsequent read-only checks:

```sh
make doctor
make macos   # optional: show extensions, Finder path bar and status bar
```

Doctor reports Foundation, Agents, Applications, and Container Runtime separately.
It checks the managed mise binary rather than an unrelated mise on PATH. VS Code
GUI without `code` gets a warning; Orca is checked as `Orca.app`. Missing OrbStack
is reported as a warning because a functioning alternative Docker backend is
accepted. Compose v2 or later and `sha256sum` or `shasum` are required.
A newer Command Line Tools warning is surfaced with macOS Software Update advice;
no deletion or reinstall is performed. Doctor never installs tools, starts a
runtime, or changes Docker contexts; bootstrap's preparation stage owns startup.
Only `make macos` applies the declared preferences and restarts Finder.

## Routine operation

All agents share one management surface:

```sh
mise ls --global     # audit the Agent layer
mise ls
mise install        # install declared resolved tools
mise upgrade        # explicitly upgrade agents together
```

Use direct global maintenance from a directory without project mise settings,
such as your home directory. No per-agent npm, Homebrew, or curl installer is
required. The complete Basecamp version-changing workflow is:

```sh
make update
git diff
```

Update preflights configuration, requires the managed mise binary, updates
Homebrew metadata and upgrades only Brewfile requirements with Bundle's
`--upgrade` mode (including auto-updating casks). It then runs managed mise
`self-update --yes --no-plugins`, `lock --global --bump`, `install --locked`, and
doctor. It stops at a failed stage. Agent updates refresh the repository's
global lockfile ([mise lockfile details](https://mise.jdx.dev/dev-tools/mise-lock.html)).
Homebrew may update dependencies required by declared packages. Unlisted packages,
including an old Homebrew mise, are not explicit upgrade targets. Cleanup and
unrelated dependent repairs are disabled in both installation and update.

`make install` runs the conservative installation stages without linking dotfiles
or running doctor. `make link` safely links global mise policy, its lock, and
dotfiles. Put local shell settings in `~/.zshrc.local` and Git identity/signing
settings in `~/.gitconfig.local`. Use normal local credential storage. Never track
credentials, agent sessions, history, or private keys. Basecamp never automatically
commits or pushes changes.

## Relationship with Foundry

Basecamp owns the Mac host: Foundation, Agents, Editor, Container Runtime, and
Orchestrator. Foundry owns Dockerfiles, Compose, project commands, development
conventions, and project containers: Node.js, Python, Ruby, Go, Java, dependencies,
databases, services, build tools, and tests.

Neither repository directly depends on the other. Foundry and its projects require
only documented generic host capabilities such as Docker, Compose v2, Git, Make,
and SHA-256 tooling. They require neither Basecamp nor OrbStack. Gemini's host
Node.js is separate from container-owned project Node.js; agents use no
OrbStack-specific APIs.
