# Neovim Testing and Debugging Plan

This document describes the plan for adding testing and debugging support to this Neovim configuration, including the maintained `neotest-dotnet` fork at `CollinRobison/neotest-dotnet`.

## Current configuration

Startup is:

```text
nvim/init.lua
  -> collin/init.lua
  -> collin/lazy_init.lua
  -> import collin.lazy
```

The configuration currently uses:

- `lazy.nvim` for plugin management.
- `mason.nvim` and `mason-lspconfig.nvim` for LSP server installation.
- Native `vim.lsp.config()` and `vim.lsp.enable()` APIs.
- `nvim-treesitter` with parsers for C#, C/C++, Go, Rust, Python, JavaScript, TypeScript, Svelte, Bash, Lua, SQL, and related formats.
- Roslyn test code lenses enabled through `lsp.lua`.
- No DAP client, test runner, test adapter, or debugger adapter yet.

The authoritative language/server list is in `nvim/lua/collin/lazy/lsp.lua`. Existing C# settings include:

```lua
["csharp|code_lens"] = {
  dotnet_enable_references_code_lens = true,
  dotnet_enable_tests_code_lens = true,
}
```

## Goals

1. Add a consistent test workflow without hiding project-native commands.
2. Add a usable debugger for the compiled and interpreted languages used here.
3. Support C# through the maintained `neotest-dotnet` fork without making the fork the only fallback.
4. Keep optional tools from breaking Neovim startup when they are not installed.
5. Keep plugin specs and language-specific configuration separated from the existing LSP configuration.
6. Pin tested plugin revisions in `nvim/lazy-lock.json`.
7. Validate each integration against real project layouts and native commands.

## Target plugin structure

Add these plugin specifications under `nvim/lua/collin/lazy/`:

```text
mason-tools.lua  -- shared Mason setup and external tool installation
 dap.lua          -- nvim-dap, DAP UI, signs, keymaps, adapters
 neotest.lua      -- Neotest and language-specific adapters
```

The exact fork URL should be used in the Neotest spec:

```lua
"CollinRobison/neotest-dotnet"
```

The fork should be pinned to a tested commit through `lazy-lock.json`.

## Core plugins

Install:

- `mfussenegger/nvim-dap`
- `rcarriga/nvim-dap-ui`
- `nvim-neotest/nvim-nio`
- `theHamsta/nvim-dap-virtual-text`
- `nvim-neotest/neotest`
- `antoinemadec/FixCursorHold.nvim`

Use `mason-nvim-dap.nvim` and/or `mason-tool-installer.nvim` only for installation plumbing. Mason installation must not be treated as automatic DAP or Neotest configuration.

## Debugger adapters

Install and configure these adapters as optional tools:

| Language | Adapter | Native prerequisite |
| --- | --- | --- |
| Python | `debugpy` | Project Python environment |
| JavaScript/TypeScript/Svelte | `js-debug-adapter` | Node.js and project dependencies |
| Go | `delve` | Go toolchain |
| Rust | `codelldb` | Rust/Cargo toolchain |
| C/C++ | `codelldb` | Clang/GCC and build system |
| C#/.NET | `netcoredbg` | Compatible .NET SDK/runtime |

DAP configuration must be language-specific. Each adapter has different launch and attach fields, so there should not be one generic executable template.

The DAP setup should include:

- Breakpoint signs.
- Continue, step, restart, pause, and terminate mappings.
- DAP UI open/close listeners.
- Inline virtual text, preferably toggleable.
- A clear notification when an adapter is missing.
- Per-language launch configurations.
- Test debugging support where the test adapter provides a DAP strategy.

## Test adapters

Start with:

| Language | Adapter | Native runner |
| --- | --- | --- |
| Python | `neotest-python` | pytest/unittest |
| JavaScript/TypeScript | `neotest-vitest`, optionally `neotest-jest` | Vitest/Jest |
| Go | `neotest-go` | `go test` |
| Rust | `neotest-rust` | `cargo test` |
| C# | `CollinRobison/neotest-dotnet` | `dotnet test` |
| C/C++ | `neotest-gtest` or `neotest-ctest` | GoogleTest/CTest |

Add later only when needed:

- `neotest-bash` for Bats tests.
- `neotest-plenary` or `neotest-busted` for Lua tests.
- `neotest-playwright` for browser/Svelte tests.

The C# fork is preferred over the upstream adapter because it can be updated and regression-tested for Neovim 0.12, current Neotest, and current Tree-sitter. `vim-test` should remain the fallback for direct `dotnet test` execution.

## Language coverage

### Python

- Use `neotest-python`.
- Run tests with the project's virtual environment or `uv run`.
- Keep `pytest` and `debugpy` project-aware.
- Do not assume Mason's Python is the same interpreter used by `basedpyright`.

### JavaScript, TypeScript, and Svelte

- Select Vitest when the project has Vitest configuration/dependencies.
- Select Jest when the project has Jest configuration/dependencies.
- Use `js-debug-adapter` for Node and browser debugging.
- Preserve source-map support for TypeScript and Svelte.
- Add Playwright only for projects that actually use it.

### Go

- Use `neotest-go` and `delve`.
- Respect `go.mod`, workspaces, build tags, and package roots.
- Validate nearest test, package test, and `go test ./...`.

### Rust

- Use `neotest-rust` and `codelldb`.
- Install Rust/Cargo before enabling Rust test/debug checks.
- Respect workspaces, features, and target selection.
- Validate nearest test and `cargo test`.

### C and C++

- Use `neotest-gtest` for GoogleTest projects or `neotest-ctest` for CMake/CTest projects.
- Use `codelldb` for debugging.
- Require a configured build tree for CTest.
- Do not promise test discovery for arbitrary C/C++ projects without a supported test framework.

### C#/.NET

- Use the maintained `CollinRobison/neotest-dotnet` fork.
- Keep `dotnet test` as the execution backend.
- Support NUnit, xUnit, and MSTest.
- Configure `netcoredbg` separately through DAP.
- Use solution discovery for multi-project solutions and project discovery for focused projects.
- Preserve Roslyn test code lenses as a lightweight alternative.
- Keep `vim-test` available as a reliable direct-run fallback.

### Bash and Lua

These are lower priority:

- Bash: Bats plus `neotest-bash`; use shell tracing before attempting full DAP support.
- Lua: Plenary or Busted testing; use Neovim logging and messages rather than assuming a standard Lua debugger.

### SQL, GraphQL, Prisma, Docker, markup, and config formats

These do not need standalone Neotest/DAP integrations by default:

- SQL: database-specific test and migration commands.
- GraphQL: schema validation and application tests.
- Prisma: `prisma validate`, migrations, and application tests.
- Docker: image/build/integration checks.
- HTML/CSS/Svelte: browser or application tests.
- JSON/YAML/TOML/XML: existing LSP/schema validation.
- Markdown: existing Prettier and markdownlint setup.

## Keymaps

Use the existing `<leader>` convention and reserve these groups:

```text
<leader>d  Debugging
<leader>t  Testing
```

Proposed mappings:

```text
<leader>db  Toggle breakpoint
<leader>dB  Conditional breakpoint
<leader>dc  Continue
<leader>di  Step into
<leader>do  Step over
<leader>dO  Step out
<leader>dr  Restart
<leader>dq  Terminate
<leader>du  Toggle DAP UI
<leader>de  Evaluate expression

<leader>tn  Run nearest test
<leader>tf  Run current file
<leader>ta  Run test suite
<leader>td  Debug nearest test
<leader>ts  Open test summary
<leader>to  Show test output
<leader>tx  Stop test
```

Add descriptions so the existing `which-key.nvim` integration displays them.

## Roslyn code lenses

The current LSP attach logic enables code lenses but does not provide explicit refresh/run mappings. Add buffer-local C# mappings only after verifying the Roslyn server exposes executable test lenses:

```text
<leader>lr  Refresh code lenses
<leader>lt  Run the code lens under the cursor
```

These mappings are a convenience feature, not a replacement for suite-level Neotest or `dotnet test` commands.

## External prerequisites

The current environment already provides Node.js, Go, .NET, Clang, `uv`, Neovim, and Tree-sitter CLI through the Brewfile or local installation.

Before implementation, add or verify:

```text
Rust/Cargo
CMake/CTest
pytest in the relevant Python environment
Bats/Busted only if those test suites are used
netcoredbg
```

Do not install every test framework globally. Keep test frameworks project-local where practical:

- Python through `uv`/virtual environments.
- JavaScript/TypeScript through npm project dependencies.
- .NET frameworks through project package references.
- C/C++ frameworks through the project build system.

## Implementation phases

### Phase 1: Baseline

Record:

```bash
nvim --version
dotnet --info
node --version
go version
cargo --version
cmake --version
```

Inside Neovim, validate:

```vim
:checkhealth
:LspInfo
:Mason
:TSInstallInfo
```

Do not change existing LSP behavior during this phase.

### Phase 2: Mason and tool checks

- Centralize Mason initialization.
- Add optional adapter installation.
- Add executable checks.
- Make absent optional tools produce useful notifications rather than startup failures.

### Phase 3: DAP

- Add the core DAP plugins.
- Add UI event listeners and mappings.
- Configure Python, .NET, Go, Rust/C/C++, and JavaScript adapters.
- Validate one ordinary application launch per language.

### Phase 4: Neotest

- Add Neotest and `nvim-nio`.
- Add Python, C#, Go, Rust, and Vitest adapters.
- Use the forked C# adapter.
- Add keymaps and summary/output consumers.
- Validate native command parity.

### Phase 5: C# fork integration

- Pin `CollinRobison/neotest-dotnet` to a tested commit.
- Test NUnit, xUnit, and MSTest projects.
- Validate method, file, project, solution, and debug runs.
- Keep direct `dotnet test` and `vim-test` fallback available.

### Phase 6: Expand coverage

Add Jest, CTest/GoogleTest, Bash, Lua, and Playwright only when real projects require them. Each adapter must have a native command parity check and a documented prerequisite.

## Validation matrix

For each supported language, validate:

1. Test discovery.
2. Nearest test execution.
3. Current-file execution.
4. Suite execution.
5. Failure output and source navigation.
6. Test cancellation.
7. Debug session startup.
8. Breakpoint hit.
9. Variable inspection.
10. Clean session termination.

Compare Neotest with native commands:

```bash
dotnet test
pytest
go test ./...
cargo test
ctest --test-dir build
npm test
```

The native command remains authoritative when an editor integration and the project disagree.

## Definition of done

The implementation is complete when:

- Existing LSP and Treesitter behavior is unchanged.
- DAP UI and keymaps work without an adapter installed.
- C# test discovery works through the maintained fork on Neovim 0.12.
- NUnit, xUnit, and MSTest runs return correct statuses and output.
- C# debugging works through `netcoredbg`.
- Python, Go, Rust, and JavaScript/TypeScript support works for representative projects.
- Missing runtimes and adapters produce actionable diagnostics.
- Plugin revisions are recorded in `nvim/lazy-lock.json`.
- The fork's own CI and tests pass before the Neovim integration is considered stable.
