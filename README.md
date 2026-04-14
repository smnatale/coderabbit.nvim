# 🐰 coderabbit.nvim

[![CI](https://github.com/smnatale/coderabbit.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/smnatale/coderabbit.nvim/actions/workflows/ci.yml) [![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-green?logo=neovim&logoColor=white)](https://neovim.io) [![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-pink?logo=github)](https://github.com/sponsors/smnatale)

The first Neovim integration for [CodeRabbit](https://coderabbit.link/sam-natale) — bringing the AI code reviewing assistant to your favorite editor!

> Not affiliated with CodeRabbit — just a fan. If you sign up, using the [link above](https://coderabbit.link/sam-natale) helps me out.
<img width="2396" height="1403" alt="image" src="https://github.com/user-attachments/assets/acb8a567-e527-494c-940a-e05374a4072f" />

## Features

- **Inline diagnostics** — CodeRabbit findings show up as native Neovim diagnostics with virtual text, sign column markers, and underlines, just like a real LSP
- **Code actions** — apply suggested fixes directly from the quickfix menu (`vim.lsp.buf.code_action()`)
- **Review viewer** — read the full review in a floating window or buffer, with findings grouped by file, severity levels, and syntax-highlighted code suggestions
- **Review types** — review all changes, only committed changes, or only uncommitted changes, with optional base branch/commit comparison
- **Review history** — browse and revisit past reviews, persisted to disk across sessions
- **Statusline integration** — drop `require("coderabbit").status()` into your statusline for a live spinner while reviews run

## Getting Started

Requires Neovim >= 0.10 and the [CodeRabbit CLI](https://cli.coderabbit.ai):

```sh
curl -fsSL https://cli.coderabbit.ai/install.sh | sh
cr auth login
```

Install the plugin and call setup:

```lua
-- vim.pack (nvim 0.12)
vim.pack.add({"https://github.com/smnatale/coderabbit.nvim"})
require("coderabbit").setup()

-- lazy.nvim
{ "smnatale/coderabbit.nvim", opts = {} }
```

Run `:checkhealth coderabbit` to verify everything is wired up.

## Usage

`:CodeRabbitReview` to kick off a review. Findings show up as diagnostics with virtual text, signs, and code actions (`vim.lsp.buf.code_action()`).

| Command | |
| --- | --- |
| `:CodeRabbitReview [type]` | Run a review. Defaults to `all`, or pass `committed`/`uncommitted` |
| `:CodeRabbitStop` | Cancel a running review |
| `:CodeRabbitClear` | Clear diagnostics |
| `:CodeRabbitShow [id]` | View results (float or buffer). Defaults to the latest review |
| `:CodeRabbitRestore [id]` | Reapply diagnostics from a saved review. Defaults to the most recent |
| `:CodeRabbitHistory` | Browse past reviews |

For your statusline:

```lua
require("coderabbit").status()  -- spinner while reviewing, nil when idle
```

## Config

Defaults — everything is optional:

```lua
require("coderabbit").setup({
  cli = {
    binary = "cr",
    timeout = 0,
    extra_args = {},
  },
  review = {
    type = "all",  -- "all", "committed", or "uncommitted"
    base = nil,
    base_commit = nil,
  },
  diagnostics = {
    enabled = true,
    severity_map = {
      critical = vim.diagnostic.severity.ERROR,
      major = vim.diagnostic.severity.WARN,
      minor = vim.diagnostic.severity.INFO,
    },
    virtual_text = true,
    signs = true,
    underline = true,
  },
  show = {
    layout = "float",  -- "float" or "buffer"
    float = {
      width = 0.6,
      height = 0.7,
      border = "rounded",
    },
  },
  on_review_complete = nil,
})
```
