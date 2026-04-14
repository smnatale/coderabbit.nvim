# 🐰 coderabbit.nvim

[![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/smnatale/coderabbit.nvim?utm_source=oss&utm_medium=github&utm_campaign=smnatale%2Fcoderabbit.nvim&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)](https://coderabbit.ai) [![CI](https://github.com/smnatale/coderabbit.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/smnatale/coderabbit.nvim/actions/workflows/ci.yml) [![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-green?logo=neovim&logoColor=white)](https://neovim.io)

The first Neovim integration for [CodeRabbit](https://coderabbit.link/sam-natale) — bringing the AI code reviewing assistant to your favorite editor!

> Not affiliated with CodeRabbit — just a fan. If you sign up, using the [link above](https://coderabbit.link/sam-natale) helps me out.

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
{ "coderabbitai/coderabbit.nvim", opts = {} }
```

Run `:checkhealth coderabbit` to verify everything is wired up.

## Usage

`:CodeRabbitReview` to kick off a review. Findings show up as diagnostics with virtual text, signs, and code actions (`vim.lsp.buf.code_action()`).

| Command | |
| --- | --- |
| `:CodeRabbitReview [type]` | Run a review. Defaults to `all`, or pass `committed`/`uncommitted` |
| `:CodeRabbitStop` | Cancel a running review |
| `:CodeRabbitClear` | Clear diagnostics |
| `:CodeRabbitShow [id]` | View results in a split. Defaults to the latest review |
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
  on_review_complete = nil,
})
```
