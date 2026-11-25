#!/bin/sh
# Accept no bridge-supplied CLI flags and load only our explicit Chat extension.
set -eu
set -- --mode rpc --offline --no-session --no-approve --no-mcp --no-extensions \
  --no-skills --no-prompt-templates --no-themes --no-context-files --model "$NVIM_AI_PI_MODEL"
if [ -n "${NVIM_AI_PI_CHAT_EXTENSION:-}" ]; then
  tools=workspace_list,workspace_search,workspace_read,workspace_edit,workspace_create,workspace_mkdir,workspace_move,workspace_delete
  if [ "$(/usr/bin/uname -s)" = Darwin ] && [ -x /usr/bin/sandbox-exec ]; then
    tools="$tools,workspace_run"
  fi
  set -- "$@" --no-builtin-tools --tools "$tools" --extension "$NVIM_AI_PI_CHAT_EXTENSION"
else
  set -- "$@" --no-tools
fi
exec "$NVIM_AI_PI_BINARY" "$@"
