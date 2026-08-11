#!/usr/bin/env bash
# Install the Linux-only workstation tools used by these dotfiles without root.
# This file deliberately does nothing on macOS or Windows so their existing
# dotfile workflows remain unchanged.
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Linux workstation bootstrap skipped: this host is $(uname -s)."
  exit 0
fi

case "$(uname -m)" in
  x86_64|amd64) ;;
  *)
    echo "Unsupported Linux architecture: $(uname -m). This bootstrap currently supports x86_64 only." >&2
    exit 1
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
local_root="${LOCAL_ROOT:-$HOME/.local}"
bin_dir="$local_root/bin"
opt_dir="$local_root/opt"
mkdir -p "$bin_dir" "$opt_dir" "$HOME/.config"
export PATH="$bin_dir:$PATH"

ensure_shell_path_hook() {
  local shell_rc="$1"
  local start='# >>> Collin dotfiles Linux tools >>>'
  local end='# <<< Collin dotfiles Linux tools <<<'
  [[ -f "$shell_rc" ]] || : > "$shell_rc"
  if ! grep -Fqx "$start" "$shell_rc"; then
    printf '\n%s\n[ -f "$HOME/.config/dotfiles/shell-path.sh" ] && . "$HOME/.config/dotfiles/shell-path.sh"\n%s\n' "$start" "$end" >> "$shell_rc"
    echo "Added Linux tool PATH hook to $shell_rc"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

safe_link() {
  local source="$1"
  local target="$2"
  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    echo "Already linked: $target"
    return
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    local backup="${target}.pre-dotfiles.$(date +%Y%m%d%H%M%S)"
    mv "$target" "$backup"
    echo "Backed up existing path: $target -> $backup"
  fi
  ln -s "$source" "$target"
  echo "Linked: $target -> $source"
}

backup_pi_configuration() {
  local target_root="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
  local backup_root="${target_root}.pre-dotfiles.$(date +%Y%m%d%H%M%S)"
  local item source target
  for item in AGENTS.md settings.json pi-alerts.json lsp.json keybindings.json prompts skills extensions themes agents pi-permissions.jsonc; do
    source="$repo_root/.pi/$item"
    [[ "$item" == "lsp.json" ]] && source="$repo_root/.pi/lsp-global.json"
    target="$target_root/$item"
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
      continue
    fi
    if [[ -e "$target" || -L "$target" ]]; then
      mkdir -p "$backup_root"
      mv "$target" "$backup_root/$item"
      echo "Backed up existing Pi configuration: $target -> $backup_root/$item"
    fi
  done
}

require_command curl
require_command tar
require_command git
require_command jq
require_command node
require_command npm

mkdir -p "$HOME/.config/dotfiles"
safe_link "$repo_root/Linux/shell-path.sh" "$HOME/.config/dotfiles/shell-path.sh"
ensure_shell_path_hook "$HOME/.bashrc"
ensure_shell_path_hook "$HOME/.zshrc"

# Pi coding agent and the version-controlled configuration. Back up conflicting
# public Pi configuration before the upstream linker replaces it.
if ! command -v pi >/dev/null 2>&1; then
  npm install --global --prefix "$local_root" @earendil-works/pi-coding-agent@0.84.1
fi
backup_pi_configuration
PI_DOTFILES_YES=1 "$repo_root/.pi/install.sh"

# Go is required by Mason to install gopls. Install the official Linux archive
# rootlessly when a system Go toolchain is not available.
if ! command -v go >/dev/null 2>&1; then
  go_version="${GO_VERSION:-go1.26.5}"
  go_archive_name="${go_version}.linux-amd64.tar.gz"
  go_stage="$(mktemp -d)"
  trap 'rm -rf "$go_stage"' EXIT
  curl --fail --silent --show-error --location "https://go.dev/dl/${go_archive_name}" -o "$go_stage/go.tar.gz"
  tar -xzf "$go_stage/go.tar.gz" -C "$go_stage"
  rm -rf "$opt_dir/go-${go_version}"
  mv "$go_stage/go" "$opt_dir/go-${go_version}"
  ln -sfn "$opt_dir/go-${go_version}/bin/go" "$bin_dir/go"
  trap - EXIT
  rm -rf "$go_stage"
fi

# Neovim's Treesitter configuration compiles locally installed parsers. The
# CLI is distributed as a rootless npm package and is shared by all platforms.
if ! command -v tree-sitter >/dev/null 2>&1; then
  npm install --global --prefix "$local_root" tree-sitter-cli@0.26.12
fi

# Neovim's official Linux tarball keeps this bootstrap rootless. The default is
# pinned for reproducibility; set NVIM_VERSION to select another release.
if [[ ! -x "$bin_dir/nvim" ]]; then
  nvim_version="${NVIM_VERSION:-v0.12.4}"
  nvim_stage="$(mktemp -d)"
  trap 'rm -rf "$nvim_stage"' EXIT
  archive="$nvim_stage/nvim.tar.gz"
  curl --fail --silent --show-error --location \
    "https://github.com/neovim/neovim/releases/download/${nvim_version}/nvim-linux-x86_64.tar.gz" \
    -o "$archive"
  rm -rf "$opt_dir/nvim-linux-x86_64"
  tar -xzf "$archive" -C "$opt_dir"
  trap - EXIT
  rm -rf "$nvim_stage"
  ln -sfn "$opt_dir/nvim-linux-x86_64/bin/nvim" "$bin_dir/nvim"
fi
safe_link "$repo_root/nvim" "$HOME/.config/nvim"

# Install a pinned Kitty archive directly instead of executing a downloaded shell
# script. The config itself is portable; macOS quick-access notes are comments.
if [[ ! -x "$local_root/kitty.app/bin/kitty" ]]; then
  kitty_version="${KITTY_VERSION:-0.48.2}"
  kitty_stage="$(mktemp -d)"
  trap 'rm -rf "$kitty_stage"' EXIT
  curl --fail --silent --show-error --location \
    "https://github.com/kovidgoyal/kitty/releases/download/v${kitty_version}/kitty-${kitty_version}-x86_64.txz" \
    -o "$kitty_stage/kitty.txz"
  mkdir "$kitty_stage/extract"
  tar -xJf "$kitty_stage/kitty.txz" -C "$kitty_stage/extract"
  rm -rf "$local_root/kitty.app"
  mv "$kitty_stage/extract" "$local_root/kitty.app"
  trap - EXIT
  rm -rf "$kitty_stage"
fi
safe_link "$local_root/kitty.app/bin/kitty" "$bin_dir/kitty"
safe_link "$repo_root/Kitty" "$HOME/.config/kitty"

echo
printf 'Pi: '; pi --version
printf 'Go: '; go version
printf 'Treesitter: '; tree-sitter --version
printf 'Neovim: '; nvim --version | { IFS= read -r version; printf '%s\n' "$version"; }
printf 'Kitty: '; kitty --version
printf 'Notifications: '; command -v notify-send || true
