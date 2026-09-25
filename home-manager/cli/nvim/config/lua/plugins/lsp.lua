local is_termux = require("utils").is_termux()

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        lua_ls = {
          -- do not install with meson on termux, it just fails
          mason = not is_termux,
        },
        -- cargo...
        ruff = {
          -- do not install with meson on termux, it just fails
          mason = not is_termux,
        },
        ruff_lsp = {
          -- do not install with meson on termux, it just fails
          mason = not is_termux,
        },
        -- https://github.com/oxalica/nil/blob/main/docs/configuration.md
        nil_ls = {
          mason = not is_termux,
          settings = {
            ["nil"] = {
              nix = {
                flake = {
                  -- Automatically run `nix flake archive` when necessary
                  autoArchive = true,
                  -- Whether to auto-eval flake inputs. Can be costly (cpu/mem)
                  autoEvalInputs = false,
                },
              },
            },
          },
        },
        yamlls = {
          settings = {
            yaml = {
              schemas = require("schemastore").yaml.schemas(),
            },
          },
        },
      },
    },
  },

  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      if is_termux then
        opts.ensure_installed =
          require("utils").remove_element(opts.ensure_installed, "stylua")
      end
    end,
  },
}
