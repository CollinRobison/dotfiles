# Pi configuration

This directory contains the public, non-sensitive Pi configuration for these dotfiles.

## Install

From the repository root, run:

```bash
./.pi/install.sh
```

The installer links these files into `~/.pi/agent/` and asks before replacing existing files:

- `AGENTS.md`
- `settings.json`
- `pi-alerts.json`
- `lsp-global.json` (linked as `lsp.json`)
- `keybindings.json`
- `prompts/`
- `skills/`
- `extensions/`
- `themes/`
- `agents/`
- `pi-permissions.jsonc`

It does not touch Pi credentials, sessions, or generated model data. Restart Pi or use `/reload` afterward.

## Custom agents

The global agents are version-controlled here and linked to `~/.pi/agent/agents` by the installer:

- `/agent normal` — the normal Pi agent with the existing permissive behavior
- `/agent cautious` — reads within the project automatically and asks before changes, commands, MCP, and external paths
- `/agent reviewer` — read-only review agent; mutations, commands, MCP, and external paths are denied
- `/agents` — list available agents

Permission prompts can be temporarily auto-approved for the current session with `/allow-all`. Use `/ask-all` to restore prompts. This does not persist the setting.

Pi alerts are controlled by `pi-alerts.json` and are enabled explicitly there. Use `/pi-alerts status` or `/pi-alerts test` to inspect and test the notification backend.

The third-party `pi-permission-system` package is pinned in `settings.json`; Pi installs missing packages from that global settings file.

## LSP setup

`lsp-global.json` configures Pi to reuse language servers installed by Mason.nvim. The
Zsh configuration adds Mason's bin directory to `PATH` when it exists; set `MASON_BIN`
to override the default path.

On a new machine:

```bash
./.pi/install.sh
./.pi/setup-lsp.sh
```

If the check reports missing servers, open Neovim once so its `ensure_installed`
configuration can install them, then run the setup script again. Afterward, start Pi
and run the `/lsp install` commands printed by the script once to register the system
binaries in Pi's LSP lockfile. The powerline shows the configured servers detected
for the current project; use `/lsp-project` to refresh it manually.

## Security

Review extensions and skills before using them. Never commit credentials, session files, auth files, or generated package caches.
