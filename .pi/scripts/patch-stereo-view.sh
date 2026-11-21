#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
global_target="$agent_dir/npm/node_modules/pi-stereo-view/src/layout.ts"
project_target="$repo_root/.pi/npm/node_modules/pi-stereo-view/src/layout.ts"
target="${PI_STEREO_VIEW_LAYOUT:-$global_target}"
if [[ -z "${PI_STEREO_VIEW_LAYOUT:-}" && ! -f "$target" && -f "$project_target" ]]; then
  target="$project_target"
fi

if [[ ! -f "$target" ]]; then
  echo "pi-stereo-view source not found: $target" >&2
  exit 1
fi

python3 - "$target" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = '      const candidate = !!projectedDock && (widgetsPresent() || dialogPresent()) && dockUnchanged() && !this.failed &&\n'
new = (
    '      // Keep status/footer widgets in Pi\'s native full-width dock; only project an\n'
    '      // inline dialog into Activity. Otherwise side-by-side layouts squeeze bars\n'
    '      // such as pi-powerline-footer into the Activity column.\n'
    '      const candidate = !!projectedDock && dialogPresent() && dockUnchanged() && !this.failed &&\n'
)
if new in source:
    print(f"Already patched: {path}")
elif old in source:
    path.write_text(source.replace(old, new, 1))
    print(f"Patched full-width status/footer widgets: {path}")
else:
    raise SystemExit(
        f"Patch anchor not found in {path}; pi-stereo-view changed. "
        "Inspect the layout before updating this patch."
    )
PY
