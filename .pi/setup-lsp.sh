#!/usr/bin/env bash
set -euo pipefail

mason_bin="${MASON_BIN:-$HOME/.local/share/nvim/mason/bin}"
servers=(
  vtsls
  basedpyright-langserver
  gopls
  rust-analyzer
  yaml-language-server
  vscode-json-language-server
)

if [[ ! -d "$mason_bin" ]]; then
  echo "Mason bin directory was not found: $mason_bin" >&2
  echo "Open Neovim once to bootstrap Mason, then run this script again." >&2
  exit 1
fi

missing=()
for server in "${servers[@]}"; do
  if [[ ! -x "$mason_bin/$server" ]]; then
    missing+=("$server")
  fi
done

if ((${#missing[@]} > 0)); then
  printf 'Missing Mason language servers in %s:\n' "$mason_bin" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "Open Neovim once so its ensure_installed list can install them." >&2
  exit 1
fi

echo "Mason language servers are ready: $mason_bin"
echo
echo "In Pi, run these once to register the system binaries:"
printf '  /lsp install %s\n' vtsls pyright gopls rust-analyzer yamlls jsonls
