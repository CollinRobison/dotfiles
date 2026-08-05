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

The third-party `pi-permission-system` package is pinned in `settings.json`; Pi installs missing packages from that global settings file.

## Security

Review extensions and skills before using them. Never commit credentials, session files, auth files, or generated package caches.
