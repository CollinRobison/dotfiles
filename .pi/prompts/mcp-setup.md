---
description: Set up a curated MCP server with a guided, safe configuration flow
argument-hint: "[github|notion|deepwiki|context7|chrome-devtools] [global|local]"
---
Set up the requested MCP server: ${1:-$ARGUMENTS}.

Follow this workflow:

1. Inspect the current MCP state with the `mcp` status tool and preserve all existing servers and settings.
2. Determine the configuration scope. Use the second argument when provided: `global` writes to `~/.config/mcp/mcp.json`; `local` writes to the current project's `.mcp.json`. If no scope is provided, ask the user to choose Global or Local before changing files. Explain that Global applies across projects while Local applies only to the current project.
3. Treat the requested name as one of these curated presets:
   - `github`: `https://api.githubcopilot.com/mcp`, OAuth
   - `notion`: `https://mcp.notion.com/mcp`, OAuth
   - `deepwiki`: `https://mcp.deepwiki.com/mcp`, no credentials normally required
   - `context7`: `https://mcp.context7.com/mcp`, no credentials normally required
   - `chrome-devtools`: local `npx -y chrome-devtools-mcp@1.6.0`
4. If the server is not already configured in the selected scope, show the exact minimal config change before making it. Preserve unrelated servers and settings. Use the adapter's `/mcp setup` flow when appropriate.
5. For OAuth servers, use the adapter's normal `/mcp-auth <server>` flow. If discovery reports that dynamic client registration is unsupported, explain that a pre-registered OAuth app is required and do not retry registration blindly.
6. For GitHub specifically, prefer the already-authenticated GitHub CLI over MCP OAuth: verify `gh auth status`, then configure the remote server with `auth: "bearer"` and `headers.Authorization: "!gh auth token"`. This lets the adapter obtain the token at connection time without copying it into config or chat. If `gh` is missing or unauthenticated, ask the user to run `gh auth login`, then retry. Only fall back to a GitHub OAuth App if the user cannot use `gh`.
7. Never print, commit, or store OAuth/PAT secrets in the repository. Use command-backed headers, environment variables, or secure credential storage.
8. After setup, validate the config, tell the user to reload MCP if needed, authenticate if needed, and verify the server with `mcp` status. Report exactly what remains for the user to do.

If the requested server is ambiguous or unsupported, ask the user to choose one of the curated presets instead of inventing a server URL.
