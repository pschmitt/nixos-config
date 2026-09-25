local bruvtab_enabled = not require("utils").is_termux()
  and (vim.fn.executable("bruvtab") == 1)

vim.g.lazyvim_blink_main = false

return {
  {
    "saghen/blink.cmp",
    dependencies = {
      {
        "saghen/blink.compat",

        -- sources
        { "Kaiser-Yang/blink-cmp-dictionary" },
        { "andersevenrud/cmp-tmux" },
        { "chrisgrieser/cmp-nerdfont" },
        { "dmitmel/cmp-digraphs" },
        { "moyiz/blink-emoji.nvim" },
        { "pschmitt/cmp-bruvtab", enabled = bruvtab_enabled },
      },
    },
    opts = {
      keymap = {
        preset = "enter",
      },

      signature = { enabled = true },

      -- Cmdline completions (:, /, ?, :!)
      cmdline = {
        enabled = true,
        keymap = {
          preset = "cmdline",
          ["<Tab>"] = { "show", "select_next" },
          ["<S-Tab>"] = { "select_prev" },
        },
        completion = {
          menu = {
            auto_show = function()
              local t = vim.fn.getcmdtype()
              -- auto-show for ":" and ":!" (shell) prompts
              return t == ":" or t == "!"
            end,
          },
        },
        -- choose sources based on cmdline type
        sources = function()
          local t = vim.fn.getcmdtype()
          if t == "/" or t == "?" then
            -- searches
            return { "buffer" }
          elseif t == ":" or t == "@" then
            -- ex-commands like :%s, :edit, etc.
            return { "cmdline", "path", "buffer" }
          elseif t == "!" then
            -- :! shell commands → paths + words from buffer
            return { "path", "buffer" }
          else
            return {}
          end
        end,
      },

      sources = {
        default = {
          "buffer",
          -- NOTE We've disabled cmdline on purpose and use
          -- our own cmdline config (see above)
          -- cmdline
          "lsp",
          "path",
          "emoji",
          "omni",
        },

        compat = {
          "bruvtab",
          "digraphs",
          "nerdfont",
          "tmux",
        },

        providers = {
          emoji = {
            module = "blink-emoji",
            name = "Emoji",
            score_offset = 15,
            opts = { insert = true },
          },
          -- allow buffer words inside Ex commands like :%s, :g, etc.
          buffer = {
            opts = {
              enable_in_ex_commands = true,
            },
          },
        },
      },
    },
  },
}
