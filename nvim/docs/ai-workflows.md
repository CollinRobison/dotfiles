# Neovim AI workflows — spec and task list

Branch: `feature/nvim-ai-workflows`. This file is the implementation and verification checklist. A mocked test does not count as a live provider check.

## Goals and scope

- Use the existing **Codex · ChatGPT** subscription for manual autocomplete and CodeCompanion by default. Ordinary LSP completion is unchanged and automatic. No AI completion occurs just from typing.
- Allow independent autocomplete and assistance provider choices. Later profiles can use GitHub Copilot, an official Claude Code subscription path, OpenRouter, or direct OpenAI/Anthropic APIs. Opt-in provider configuration must not require changing the keymaps. Do not install Minuet: the shared Neovim controller owns the preview.
- Each provider owns its sign-in; API key resolution is external to the repository. Store only non-secret profile/model IDs and lookup references, never token values. Missing tools, signed-out accounts, rate limits, and errors are visible. Never switch providers or fall back from a subscription to an API key automatically.
- The Atlas and Keymaps browser discover real Lua declarations, including descriptions and modes. The `AI assisted` category is a classifier, not a second inventory of specific shortcuts or commands.

## Editor behavior

| Input | Behavior |
| --- | --- |
| Normal `<leader>ap` / `:AICompletionProvider` | Choose an autocomplete profile. |
| Insert `<M-]>` | Request a single-line suggestion; dismiss any currently visible LSP completion popup without disabling LSP. A pending indicator appears while waiting. |
| Insert `<M-a>` | Insert exactly the current ghost-text suffix. No valid preview means no buffer change. |
| Insert exit, move, type, change buffer/window/profile, new request | Clear the preview and invalidate or cancel an in-flight result, even if the cursor moves back. |
| Normal `<leader>as` / `:AIAssistProvider` | Choose the profile for new assistance requests; existing conversations stay attached to their original provider. |
| Visual `<leader>aq` | Ask about the exact selection without applying an edit. |
| Visual `<leader>ae` | Propose an edit to the lines touched by a characterwise or linewise selection. In the diff, `ga`/`gr` accept/reject the current hunk and `g2`/`g3` accept/reject all. Blockwise Edit is unsupported. |
| Normal `<leader>ac` | Start a broader chat using the selected assistance profile; keep tool approvals enabled. |

Profile selection must not implicitly send the current buffer or expose a credential. Optional API/Claude profiles stay inactive until explicitly configured. A selected-line edit restricts where changes can apply, not necessarily the context the model can read.

## Provider paths and gates

| Profile | Completion | CodeCompanion | Requirements |
| --- | --- | --- | --- |
| Codex · ChatGPT (default) | `codex exec`, async, ephemeral read-only scratch context; no API-key overrides | `codex-acp` with `chat-gpt` auth and `gpt-6.2-astra` | Official sign-in; prefer CLI on `PATH`, macOS bundled Codex fallback |
| Copilot · GitHub | Optional `copilot.lua` completion request; normalize to a cursor-only insertion | `copilot --acp --stdio` | Official GitHub sign-in; no Copilot contribution to native LSP completion; optional plugin must not initiate requests unless selected and invoked |
| Claude Code · subscription | Isolated official `claude --print`, requiring `--safe-mode` and a verified subscription | Ask with tools disabled; Chat in the official terminal CLI; no inline Edit | Sign in with Claude Code; no API keys or extracted tokens |
| OpenRouter · API | Chat Completions; explicit model, no tools | Text-only Ask | Explicit metered profile; protected `OPENROUTER_API_KEY` or a vault lookup |
| OpenAI · API | Responses API; explicit model, no tools | Text-only Ask | Separate metered profile, not ChatGPT auth; protected `OPENAI_API_KEY` or a vault lookup |
| Anthropic · API | Messages API; explicit model, no tools | Text-only Ask | Separate metered profile, not Claude Code auth; protected `ANTHROPIC_API_KEY` or a vault lookup |

HTTP completion and Ask use explicit HTTPS endpoints and pass headers and payload to curl over stdin, outside argv and temp files. HTTP Chat and Edit are disabled: CodeCompanion v20.3.0's upstream HTTP transport writes authorization headers to a temp file and can leave it behind on errors or certain log levels. API profiles use the shared selectors and shortcuts, but their Ask replies do not use that transport. Copilot completion uses LSP document sync and shares the full named buffer for the explicit request; the other completion routes send bounded text around the cursor instead.

## Task list

- [x] Create and switch to the feature branch; preserve existing unrelated changes.
- [x] Research provider routes and run a Codex feasibility test (five real ChatGPT-auth requests; 3.42–4.33 s; headless Neovim ghost-text preview and explicit accept).
- [x] Build an async completion controller with a shared provider interface and cursor/buffer/generation validation.
- [x] Add Codex, optional Copilot and Claude CLI, and direct HTTP autocomplete backends; test protocol parsing, cancellation, context boundaries, and billing isolation.
- [x] Add ACP, Claude CLI, and safe API Ask routes; test selected-line edits, review, approvals, and the credential boundary.
- [x] Register literal Lua keymaps and commands. Verify source discovery in the regenerated Atlas PDF and the live `:Keymaps` app.
- [x] Run deterministic tests for every route, real terminal and LSP checks, and live ChatGPT-auth completion and ACP. Record the live coverage limits below.
- [x] Document installation, auth, local profiles, and verification. No test credentials or transcripts are tracked.

## Setup on another machine

1. Use Neovim 0.12 or later and install the dotfiles as usual. Lazy installs the pinned CodeCompanion release when synchronizing plugins.
2. Install the [official Codex CLI](https://developers.openai.com/codex/cli/) (or use the bundled ChatGPT app on macOS). Sign in with ChatGPT, then confirm that `codex login status` reports ChatGPT auth. Never copy its cached credentials into this repository.
3. Install the [official Codex ACP adapter](https://github.com/agentclientprotocol/codex-acp) so `codex-acp` is on Neovim's `PATH`. For example, `npm install -g @agentclientprotocol/codex-acp@2.12.0`. The adapter and CLI are separate; autocomplete does not need the adapter. `:echo executable('codex-acp')` should show `1` before trying Ask, Edit, or Chat.
4. Try `<M-]>` and `<M-a>` in Insert mode in a scratch file. Use `V` and `<leader>aq` or `<leader>ae` on a selected line. Find the shortcuts and provider commands under **AI assisted** in `:Keymaps` or `:KeymapAtlas`.

The shared Kitty configuration uses Left Option as Alt; Right Option still types Unicode. Restart Kitty to apply that setting, or use the equivalent option in another terminal. Sign in on each machine instead of syncing credentials.

Codex ACP uses the explicit model above because the adapter's inherited default was rejected by this ChatGPT account. If that model is unavailable on another account, add a local `codex` profile with a different supported `model` and select it for assistance. The route does not fall back to metered billing. Read-only ACP and approvals do not make the provider's native CLI or its configuration a universal sandbox; use them with trusted local tools and configuration.

### Optional local profiles

Optional profiles are read at startup from `stdpath("state")/ai-workflows/profiles.json`, or from the path named by `NVIM_AI_PROFILE_FILE`. Keep this file outside the checkout. Restart Neovim after changes. Select the provider with `:AICompletionProvider` or `:AIAssistProvider`; profiles can opt into each workflow independently. The default Codex workflow does not require any of the optional provider tools.

Example with secret *references* only. Choose model IDs available on your own account. API use is explicit and metered.

```json
[
  {
    "id": "github-copilot",
    "label": "Copilot · GitHub",
    "backend": "copilot",
    "completion": true,
    "companion": true
  },
  {
    "id": "claude-subscription",
    "label": "Claude Code · subscription",
    "backend": "claude",
    "completion": false,
    "companion": true
  },
  {
    "id": "openrouter-completion",
    "label": "OpenRouter · my completion model",
    "backend": "openrouter",
    "model": "provider/model",
    "completion": true,
    "companion": false,
    "key_ref": { "type": "keychain", "service": "nvim-openrouter" }
  }
]
```

Key references may also use `{"type":"env","name":"OPENROUTER_API_KEY"}` (inject the value only into the editor process) or `{"type":"onepassword","reference":"op://vault/item/credential"}` (requires the 1Password CLI). Do not put the key value in this JSON, a tracked `.env`, plugin options, shell history, or terminal launch arguments. An absent credential should fail only the explicitly chosen request. For API Ask, set `companion` to `true`; the assistance picker labels the profile **Ask only**. For Copilot, use `:Copilot auth` for the optional completion plugin and `copilot login` for the separate ACP CLI, if they require sign-in. Claude uses its existing Claude Code sign-in; restart Neovim after adding a profile.

## Verification log

- **Live Codex completion:** the final mappings used the bundled macOS CLI and the existing ChatGPT sign-in with API overrides removed. A scratch-buffer preview appeared in 4.3 s and changed nothing until accepted; only the cursor insertion was applied.
- **Live Codex ACP (2.12.0):** Visual Ask returned an answer without editing the source. Inline Edit proposed a diff; Reject All kept the original, Accept All kept only the selected-line change, and undo restored the original. A fresh Chat with approvals enabled completed a manually submitted turn. The adapter test used an isolated npm install, not a global install.
- **Neovim and LSP:** real TUI input over a PTY decoded both Kitty Alt sequences. A separate smoke test with real `clangd` and a stub AI backend verified that automatic LSP completion worked before and after the AI handoff. No changes to the LSP configuration were needed.
- **Mocked/fixture coverage:** `controller.lua` and `mappings.lua` cover profile independence and persistence, stale/cancelled responses, insertion, private-buffer refusal, and visual dispatch. `backends_spec.lua` and `backends_copilot_spec.lua` exercise all six completion backends. `companion.lua` uses pinned CodeCompanion with local Codex and Copilot ACP fixtures, mocked Claude CLI, and dummy credentials for the three HTTP Ask routes. Run the Lua tests with `nvim --clean --headless -i NONE -l nvim/tests/ai/<file>.lua`; for `companion.lua`, also set `CODECOMPANION_RTP` and `PLENARY_RTP` to local plugin checkouts.
- **Discovery:** the Atlas was generated with the usual runtime audit. Its extracted PDF text contains all seven AI mappings and both selector commands. `test_discovery.py` passed, and headless Chromium found all nine entries under **AI assisted**, including read-only Ex commands with the correct details.
- **Not live-tested:** Copilot and Claude inference require eligible provider sign-ins; no OpenAI, Anthropic, or OpenRouter API requests were made. HTTP Chat/Edit remain disabled by design.
