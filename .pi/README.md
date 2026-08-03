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

It does not touch Pi credentials, sessions, or generated model data. Restart Pi or use `/reload` afterward.

## Security

Review extensions and skills before using them. Never commit credentials, session files, auth files, or generated package caches.
