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
- `pi-alerts.json`
- `lsp-global.json` (linked as `lsp.json`)
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

Pi alerts are controlled by `pi-alerts.json` and are enabled explicitly there. Completion and error states also update the terminal tab title (`⏳`, `✅`, or `❌`) so the tab remains visibly marked until the next task. Use `/pi-alerts status` or `/pi-alerts test` to inspect and test the notification backend.

The third-party `pi-permission-system` package is pinned in `settings.json`; Pi installs missing packages from that global settings file.

## MCP server integration

The `pi-mcp-adapter` package adds MCP support to Pi. It is installed in `settings.json`; reload Pi after installing or changing the package:

```text
/reload
/mcp
```

No server is configured by default. Use `/mcp setup` for guided setup, or create a standard MCP configuration file. The adapter supports local stdio servers and remote HTTP servers.

Configuration locations, from shared/global sources to Pi-specific overrides, include:

- `~/.config/mcp/mcp.json` — shared user configuration
- `~/.agents/mcp.json` and `~/.agents/mcp/mcp.json` — tool-agnostic user configuration
- `~/.pi/agent/mcp.json` — Pi global override
- `.mcp.json` — project-local shared configuration
- `.pi/mcp.json` — Pi project override

Example project configuration:

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    }
  }
}
```

Servers are lazy by default and MCP tools are exposed through a token-efficient proxy. Use `directTools: true` or a tool-name list for small sets of frequently used tools. Useful commands include:

- `/mcp` — inspect servers, connection state, and proxy/direct tool settings
- `/mcp setup` — scaffold configuration or add a known server
- `/mcp tools` — list available MCP tools
- `/mcp reconnect [server]` — connect or reconnect a server
- `/mcp-auth [server]` — authenticate an OAuth server
- `/mcp disable <server>` and `/mcp enable <server>` — add/remove a project-local disable override

MCP servers can execute local commands or access external services. Review server source and configuration before enabling them, keep servers lazy unless eager startup is needed, use `approveTools` for destructive operations, and keep API keys in environment variables or OAuth—not committed configuration files.

## Subagents

The `pi-subagents` package adds focused child Pi agents. It requires no additional configuration for the built-in agents. Ask Pi naturally:

```text
Use scout to inspect the authentication flow without editing files.
Use oracle to challenge this implementation plan.
Run parallel reviewers for correctness, tests, and security.
Have worker implement the approved plan, then run reviewer.
```

Built-in roles include:

- `scout` — fast codebase reconnaissance
- `researcher` — web and documentation research
- `worker` — implementation
- `reviewer` — code review and small fixes
- `oracle` — second opinion without editing
- `delegate` — general-purpose delegation

Foreground work streams in the conversation. Background work can be inspected with `/subagents-fleet`. Other useful commands are `/subagents` (inspect/configure agents), `/subagents-stop`, `/subagents-doctor`, `/parallel-review`, `/parallel-research`, and `/review-loop`.

Custom agents are Markdown files in `~/.pi/agent/agents/` (global) or `.pi/agents/` (project). Project definitions override global and package definitions with the same name. Example:

```markdown
---
name: security-auditor
description: Read-only security reviewer
tools: read, grep, find, ls
thinking: high
---

Review code for security issues. Do not modify files.
```

Restrict child tools explicitly for read-only agents, use fresh-context reviewers for independent opinions, and use worktree isolation when multiple agents may edit the same repository. The recommended implementation loop is: clarify → scout → worker → fresh reviewers → worker.

This repository's `.pi/agents/reviewer.md` intentionally overrides the package reviewer with a read-only policy. Review agent definitions before adding or enabling agents because child Pi processes can inherit tools, extensions, skills, and project context.

## Welcome dashboard

`extensions/collin-powerline-welcome.ts` shows `/mcp` and `/subagents` in its useful-commands card. The project card also reports configured MCP server count and discovered subagent definitions, including package built-ins and global/project Markdown agents. Run `/welcome` to show it again after dismissing it.

## LSP setup

`lsp-global.json` configures Pi to reuse language servers installed by Mason.nvim. The
Zsh configuration adds Mason's bin directory to `PATH` when it exists; set `MASON_BIN`
to override the default path.

On a new machine:

```bash
./.pi/install.sh
./.pi/setup-lsp.sh
```

If the check reports missing servers, open Neovim once so its `ensure_installed`
configuration can install them, then run the setup script again. Afterward, start Pi
and run the `/lsp install` commands printed by the script once to register the system
binaries in Pi's LSP lockfile. The powerline shows the configured servers detected
for the current project; use `/lsp-project` to refresh it manually.

## External project context

`pi-add-dir` and the local `external-dir-autocomplete` extension support working
across projects without changing Pi's working directory. Add a trusted project
with `/add-dir /path/to/project`; its files then appear in `@` completion and are
inserted as absolute file attachments. Only directories explicitly added to the
current session are searched. The autocomplete extension reads paths only, skips
symlinks, `.git`, `node_modules`, and Pi runtime caches, and does not execute
external-project code. This setup also disables `pi-add-dir`'s automatic
LLM-callable `add_directory` tool; directories must be added explicitly with
`/add-dir`.

Use `/dirs` to inspect the active external directories and `/remove-dir` to revoke
one. External `AGENTS.md`/`CLAUDE.md` files are still instructions, so only add
projects you trust.

## Model pricing

Use `/models-cost` for a separate picker of all authenticated models. It displays Pi's current catalog rates per million tokens, cache-read/cache-write rates, context limits, and long-context pricing tiers. Values are API-equivalent estimates; subscription/OAuth billing may differ. Use `/models-cost scoped` to show only `enabledModels`. The command refreshes Pi's model catalog in the background and does not modify the built-in `/model` picker.

## Questionnaires

The separate `extensions/pi-questionnaire.ts` extension provides the LLM-callable `question` and `questionnaire` tools. `questionnaire` supports revisitable multi-question tabs, explicit `multiSelect` checkbox questions, `Other / write your own`, and a final review step.

Every question is required before submission, including multi-select questions. Free-text `Other / write your own` is available by default for every question; callers can explicitly set `allowOther: false` to hide it. `pi-alerts` only supplies notifications while input is needed.

## Security

Review extensions and skills before using them. Never commit credentials, session files, auth files, or generated package caches.
