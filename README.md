# Dotfiles

This is a repo for dotfiles I use.

## Pi configuration

Public, non-sensitive Pi configuration lives in [`.pi/`](.pi/).

Install it interactively with:

```bash
./.pi/install.sh
```

The installer asks before overwriting existing Pi files and links the shared configuration into `~/.pi/agent/`. It does not copy credentials, sessions, or generated model data. See [`.pi/README.md`](.pi/README.md) for details.
