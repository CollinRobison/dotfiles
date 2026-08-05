#!/usr/bin/env bash
set -euo pipefail

# Install the public Pi configuration from this repository into ~/.pi/agent.
# Credentials, sessions, and generated model data are intentionally not touched.

if [[ ! -t 0 && "${PI_DOTFILES_YES:-}" != "1" ]]; then
  echo "This installer asks before overwriting files and must be run interactively." >&2
  echo "Set PI_DOTFILES_YES=1 only when intentionally running unattended." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="$repo_root/.pi"
target_root="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

mkdir -p "$target_root"

link_item() {
  local source="$1"
  local target="$2"

  if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
    echo "Already linked: $target"
    return
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    if [[ "${PI_DOTFILES_YES:-}" == "1" ]]; then
      answer="y"
    else
      printf 'Overwrite %s? [y/N] ' "$target"
      read -r answer
    fi
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
      echo "Skipped: $target"
      return
    fi
    rm -rf "$target"
  fi

  ln -s "$source" "$target"
  echo "Linked: $target -> $source"
}

link_item "$source_root/AGENTS.md" "$target_root/AGENTS.md"
link_item "$source_root/settings.json" "$target_root/settings.json"
link_item "$source_root/keybindings.json" "$target_root/keybindings.json"
link_item "$source_root/prompts" "$target_root/prompts"
link_item "$source_root/skills" "$target_root/skills"
link_item "$source_root/extensions" "$target_root/extensions"
link_item "$source_root/themes" "$target_root/themes"
link_item "$source_root/agents" "$target_root/agents"
link_item "$source_root/pi-permissions.jsonc" "$target_root/pi-permissions.jsonc"

echo "Pi dotfiles installed. Restart Pi or run /reload."
echo "Available agents: /agent normal, /agent cautious, /agent reviewer"
echo "Session permission shortcut: /allow-all (restore with /ask-all)"
