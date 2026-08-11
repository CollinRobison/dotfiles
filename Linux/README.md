# Linux workstation bootstrap

Run this on Linux after cloning the dotfiles repository:

```bash
Linux/install-workstation.sh
```

It installs rootless copies of Pi, Go, tree-sitter, Neovim, and Kitty under `~/.local`; links the Pi, Neovim, and Kitty configurations from this repository; and makes Mason language servers available in future Bash sessions.

- Existing configuration paths are backed up before a symlink is created.
- Pi credentials, sessions, and generated model data remain untouched.
- On macOS and Windows the script exits without changing anything.
- The bootstrap defaults to pinned tool versions; set `NVIM_VERSION=vX.Y.Z`, `GO_VERSION=goX.Y.Z`, or `KITTY_VERSION=X.Y.Z` to override one deliberately.
