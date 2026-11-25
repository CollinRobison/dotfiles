# Neovim AI Guide

This is the AI companion to the [Neovim Atlas](Nvim-Dark-Complete-Atlas.pdf). The setup has two independent workflows: **on-demand autocomplete** and **Ask, Edit, and Chat**. The dotfiles select **Pi · OpenAI Luna** for autocomplete and **Pi · OpenAI** for Ask, Edit, and Chat. You can switch either workflow to **Codex · ChatGPT**, which uses your subscription sign-in without an API key and supports reviewed inline edits.

## Setup

Use Neovim 0.12 or later with this dotfiles configuration. Lazy installs the pinned CodeCompanion plugin when it is missing. For the selected Pi profiles, follow [Use Pi for completion and CodeCompanion](#use-pi-for-completion-and-codecompanion). If you prefer Codex:

1. Select **Codex · ChatGPT** in the relevant provider picker (see [Commands and shortcuts](#commands-and-shortcuts)).
2. For autocomplete, install the [Codex CLI](https://developers.openai.com/codex/cli/) and sign in with ChatGPT. On macOS, Neovim can use the CLI bundled with the Codex or ChatGPT app if `codex` isn't on `PATH`. If you use a standalone CLI, `codex login status` should report ChatGPT authentication.
3. For Ask, Edit, and Chat, install the separate [Codex ACP adapter](https://github.com/agentclientprotocol/codex-acp) with npm:

   ```sh
   npm install -g @agentclientprotocol/codex-acp@2.12.0
   codex-acp --version
   ```

   Restart Neovim and run `:echo executable('codex-acp')`. If it prints `0`, add the npm global bin directory (`$(npm prefix -g)/bin` on macOS/Linux) to the `PATH` of the shell that launches Neovim. Autocomplete does not need this adapter.

4. On macOS, quit and reopen Kitty to load the setting that makes **Left Option** act as Alt. Right Option still types Unicode. If you use another terminal, configure it to send Alt for these keys.

## Commands and shortcuts

`<leader>` is **Space** in this config. `<M-…>` means **Alt**, or **Left Option** in Kitty on macOS.

| Mode | Key or command | Action |
| --- | --- | --- |
| Insert | `<M-]>` | Request one single-line suggestion. |
| Insert | `<M-a>` | Accept the current suggestion at the cursor. |
| Normal | `<leader>ap` or `:AICompletionProvider` | Choose the autocomplete profile. |
| Normal | `<leader>as` or `:AIAssistProvider` | Choose the profile for new Ask, Edit, and Chat requests. |
| Visual | `<leader>aq` | Ask about the selection without editing it. |
| Visual | `<leader>ae` | Propose an edit to the selected lines and open a diff for review. Works with Pi, Codex, or Copilot assistance profiles. |
| Normal | `<leader>ac` | Start a fresh chat with the selected assistance profile. |

Run `:Keymaps` and search **AI assisted** for these mappings and commands. `:KeymapAtlas` regenerates and opens the PDF.

### Autocomplete

In Insert mode, press `<M-]>`. A pending indicator appears while the provider works. The result is ghost text: it does not change the buffer until you press `<M-a>`. Keep typing, move the cursor, or leave Insert mode to dismiss it. Ordinary LSP completion remains automatic; the AI shortcut closes its current popup without disabling it. Typing by itself does not request an AI suggestion.

**To reject a suggestion and try another:** Press `<M-]>` again without moving the cursor. It discards the current preview and sends a fresh request without changing your text. The provider may return the same suggestion. To dismiss it without another request, move the cursor, keep typing, or press `Esc`.

### Ask, Edit, and Chat

- **Ask:** Select code and press `<leader>aq`, then enter a question. The question includes the selected text. The answer does not change the source buffer.
- **Edit:** Select code with `v` or `V`, press `<leader>ae`, and describe the change. Edits can affect the whole lines touched by the selection, even when you select only part of a line. Blockwise Edit is unsupported. In the diff, `ga` accepts the current hunk, `gr` rejects it, `g2` accepts all remaining hunks, and `g3` rejects all remaining hunks. Pi receives only the selected lines and proposes a replacement in a separate review split. The source stays unchanged until you finish the review. Press `q` in that split to close it without applying anything.
- **Chat:** Press `<leader>ac` and type your message. In CodeCompanion, press `Esc` then `Enter` to send it. Chat starts with tool approvals enabled and doesn't submit automatically. Changing the assistance profile doesn't switch providers in existing chats.

**To reject a proposed edit and try again:** Press `g3` to reject the entire diff. Reselect the lines, press `<leader>ae`, and give a revised prompt describing what you want done differently.

## Profiles and model selection

Edit [`nvim/ai-workflows/profiles.json`](../ai-workflows/profiles.json) in the dotfiles. Neovim reads it as `stdpath('config')/ai-workflows/profiles.json` (usually `~/.config/nvim/ai-workflows/profiles.json`). If you set `NVIM_AI_PROFILE_FILE`, Neovim reads that file **instead**, which is useful for machine-specific profiles. The old state-directory `profiles.json` is no longer read by default.

Each entry has a unique `id`, a picker `label`, a `backend`, and an optional `model` (required for Pi and API profiles). Set `completion` or `companion` to `true` to make it available in that picker. API profiles also require a `key_ref`, which points to an external secret. Never put actual credentials in either profile file. Pi and Codex use their own sign-ins.

Active choices are saved in [`nvim/ai-workflows/selection.json`](../ai-workflows/selection.json), next to the profiles. It stores only two profile IDs, `completion` and `companion`. Changing either picker updates this file in the checkout; you can also edit it directly and restart Neovim. The old state-directory selection file is no longer used. If the config selection file is missing, both workflows start on Codex.

Keep IDs stable when changing labels or models so saved selections still work. If you override `profiles.json` with `NVIM_AI_PROFILE_FILE`, keep the selected IDs available in that file or choose new ones. The built-in Codex profile uses the CLI's default model for autocomplete and `gpt-6.2-astra` for assistance.

### Change models in a chat

In a CodeCompanion chat, press `Esc`, then `ga`. Select the current adapter, then choose a model. For ACP chats (Pi, Codex, or Copilot), the menu comes from the connected agent, so you don't need a JSON entry for each model. The agent decides which models it advertises and can still reject a model your account can't use. Pi shows only models from the OAuth provider selected by the profile.

The choice applies to that chat. It doesn't change the default for new chats, Ask, Edit, or autocomplete. Use the assistance profile picker to start a new chat with a different provider. Claude's native terminal chat uses its own model controls; the API routes here are Ask-only and don't have a CodeCompanion chat picker.

### Change the defaults independently

1. Add or edit entries in the profile file. For example, to use different Codex models while keeping the same ChatGPT sign-in:

   ```json
   [
     {
       "id": "codex-completion",
       "label": "Codex · Luna completion",
       "backend": "codex",
       "model": "gpt-6-luna",
       "completion": true
     },
     {
       "id": "codex-assistance",
       "label": "Codex · Astra assistance",
       "backend": "codex",
       "model": "gpt-6.2-astra",
       "companion": true
     }
   ]
   ```

   Use model IDs available to your account. Set both `completion` and `companion` to `true` if you want a profile in both pickers.

2. Restart Neovim. Run `:AICompletionProvider` (`<leader>ap`) to choose the autocomplete profile and `:AIAssistProvider` (`<leader>as`) to choose the assistance profile. Open a new chat to use the new assistance profile.

Reasoning effort and temperature aren't configurable through the profile file.

## Optional providers

You can add profiles without changing the shortcuts. The selectors remember their choices separately, and a failed request does not switch providers or fall back to API billing.

| Provider | Autocomplete | Assistance | Setup |
| --- | --- | --- | --- |
| Codex · ChatGPT | Codex CLI | CodeCompanion Ask, Edit, and Chat via Codex ACP | Sign in with ChatGPT. The default ACP model is `gpt-6.2-astra`; add a local `codex` profile with an explicit model if your account needs a different one. |
| GitHub Copilot | Optional `copilot.lua` plugin | CodeCompanion Ask, Edit, and Chat via Copilot ACP | Use `:Copilot auth` for the completion plugin and `copilot login` for the separate Copilot CLI if they require sign-in. Completion shares the full named buffer on request. |
| Claude Code | Official CLI in safe mode | Text-only Ask and native terminal Chat; no inline Edit | Install `claude` with `--safe-mode` support and sign in to an eligible Claude Code subscription. |
| Pi | Pi RPC; tools disabled | CodeCompanion Ask, reviewed Edit, and Chat via `pi-acp` | Pi 1.x, a saved OAuth sign-in, and an exact `provider/model` ID. The ACP launcher supports macOS and Linux. |
| OpenRouter, OpenAI, Anthropic | Direct HTTPS requests | Text-only Ask; no Edit or Chat | Specify a model and an external API-key reference. Usage is metered. |

### Use Pi for completion and CodeCompanion

1. Confirm Pi has a saved OAuth login with `pi auth check --provider openai` and find an available model with `pi --list-models`. Use the provider and model exactly as listed. These routes do not use API keys.
2. For CodeCompanion Ask, Edit, and Chat, install `npm install -g pi-acp@0.0.35` and check `:echo executable('pi-acp')` in Neovim. Pi autocomplete only needs `pi` on `PATH`.
3. In `:AICompletionProvider`, select **Pi · OpenAI Luna** (`openai/gpt-6-luna`) for lower-cost suggestions. In `:AIAssistProvider`, select **Pi · OpenAI** (`openai/gpt-6.2-astra`) for Ask, Edit, and Chat. Both profiles are already in the dotfiles. You can also pick Pi for one workflow and keep Codex for the other.

Pi autocomplete, Ask, and Visual Edit run without tools. For Visual Edit, Pi proposes text and Neovim applies only the approved changes to the selected lines. If the source changes while the diff is open, Neovim won't apply the proposal.

**Pi Chat can work on files.** Open it with `<leader>ac` from your project directory. Pi can list directories, search recursively by filename or literal text, and read UTF-8 files up to 128 KB. Its file tools skip hidden paths, symlinks, and common credential filenames. Pi can batch several replacements in one file, create a file, or delete a file. For a text change, `g2` approves the diff once, and `g3` or `q` rejects it. Moving a file, creating a directory, or creating or deleting an empty file uses an explicit confirmation menu. Pi won't overwrite an existing file when moving or creating a file, delete directories, or write over an unsaved buffer. Approvals still apply in auto or yolo mode.

**Attach a screenshot.** In Pi Chat, use CodeCompanion's `/file` command to attach an image. Choose a model that supports image input; changing the model with `ga` affects only that chat.

On macOS, Pi Chat can also request one-time approval to run a shell command, such as a test or linter. Commands run with a read-only workspace, no network, and a writable scratch directory. If `.venv/bin/python` points to a `uv`-managed Python under `~/.local/share/uv/python`, the sandbox grants read-only access to that Python installation only. Use `.venv/bin/python` directly or `uv run --no-sync` with an already-installed environment. Commands that need to install dependencies, access other files outside the sandbox, or write into the workspace may fail. Other platforms have the file tools but no shell tool. Pi Chat does not load project or user extensions or MCP servers. Use `ga` in a chat to switch models within the chat's signed-in provider.

### Use OpenRouter for completion and Ask

Add a profile like this to the profile JSON array:

```json
[
  {
    "id": "openrouter",
    "label": "OpenRouter",
    "backend": "openrouter",
    "model": "provider/model",
    "completion": true,
    "companion": true,
    "key_ref": { "type": "env", "name": "OPENROUTER_API_KEY" }
  }
]
```

Replace `provider/model` with a model available on your account. Key references can also point to a macOS Keychain service (`{"type":"keychain","service":"nvim-openrouter"}`) or a 1Password CLI item (`{"type":"onepassword","reference":"op://vault/item/credential"}`). Keep the actual keys out of the JSON and the repository. API Ask sends credentials to `curl` over stdin; API Chat and Edit are disabled because the pinned CodeCompanion HTTP transport can leave authorization headers in temporary files.
