#!/usr/bin/env bash
set -euo pipefail

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Playwright skill requires both node and npm on PATH." >&2
  exit 1
fi

required_version="$(node -p "require('$skill_dir/package.json').dependencies.playwright")"
installed_version=""
if [[ -f "$skill_dir/node_modules/playwright/package.json" ]]; then
  installed_version="$(node -p "require('$skill_dir/node_modules/playwright/package.json').version")"
fi

if [[ "$installed_version" != "$required_version" ]]; then
  echo "Installing Playwright $required_version..."
  npm install \
    --prefix "$skill_dir" \
    --no-package-lock \
    --no-audit \
    --no-fund \
    --loglevel warn
else
  echo "Playwright npm dependency is ready: $installed_version"
fi

if [[ "${PLAYWRIGHT_SKIP_BROWSER_INSTALL:-0}" == "1" ]]; then
  echo "Skipped Chromium installation (PLAYWRIGHT_SKIP_BROWSER_INSTALL=1)."
else
  echo "Ensuring Playwright Chromium is installed..."
  "$skill_dir/node_modules/.bin/playwright" install chromium
fi

echo "Playwright browser skill is ready."
