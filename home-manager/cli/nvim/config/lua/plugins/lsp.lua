local is_termux = require("utils").is_termux()

local termux_servers = {
  gopls = true,
  lua_ls = true,
  marksman = true,
  ruff = true,
  taplo = true,
  ty = true,
}

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = vim.tbl_deep_extend("force", opts.servers, {
        lua_ls = {
          -- do not install with meson on termux, it just fails
          mason = not is_termux,
        },
        marksman = {
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
      })

      if is_termux then
        -- Only start language servers that are part of the Termux APT profile.
        -- This prevents LazyVim extras from trying unavailable Linux/Mason tools.
        for server, server_opts in pairs(opts.servers) do
          if server ~= "*" then
            server_opts = type(server_opts) == "table" and server_opts or {}
            server_opts.enabled = termux_servers[server] == true
            server_opts.mason = false
            opts.servers[server] = server_opts
          end
        end

        for server in pairs(termux_servers) do
          local server_opts = opts.servers[server]
          server_opts = type(server_opts) == "table" and server_opts or {}
          server_opts.enabled = true
          server_opts.mason = false
          opts.servers[server] = server_opts
        end
      end
    end,
  },

  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      if is_termux then
        opts.ensure_installed = {}
      end
    end,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = function(_, opts)
      if is_termux then
        opts.ensure_installed = {}
      end
    end,
  },
}
