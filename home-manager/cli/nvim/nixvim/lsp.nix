{ lib, pkgs, ... }:
{
  # Default server configs (cmd, filetypes, root markers) from nvim-lspconfig;
  # nixvim enables the servers through vim.lsp.enable() and puts each
  # server's package on PATH.
  plugins.lspconfig.enable = true;

  lsp = {
    # Copilot ghost text (accepted with <Tab>, see completion.nix)
    inlineCompletion.enable = true;
    inlayHints.enable = true;

    servers = {
      ansiblels = {
        enable = true;
        package = pkgs.ansible-language-server;
      };
      bashls.enable = true;
      copilot.enable = lib.mkDefault true;
      docker_compose_language_service.enable = true;
      dockerls.enable = true;
      gopls.enable = true;
      jsonls.enable = true;
      jsonnet_ls.enable = true;
      lua_ls = {
        enable = true;
        config.settings.Lua = {
          workspace.checkThirdParty = false;
          diagnostics.globals = [
            "vim"
            "Snacks"
          ];
        };
      };
      marksman.enable = true;
      # https://github.com/oxalica/nil/blob/main/docs/configuration.md
      nil_ls = {
        enable = lib.mkDefault true;
        config.settings.nil.nix.flake = {
          # Automatically run `nix flake archive` when necessary
          autoArchive = true;
          # Whether to auto-eval flake inputs. Can be costly (cpu/mem)
          autoEvalInputs = false;
        };
      };
      pyright.enable = true;
      ruff.enable = true;
      taplo.enable = true;
      terraformls.enable = true;
      yamlls.enable = true;
    };
  };

  # JSON and YAML schemas for jsonls/yamlls, read when one of them starts:
  # require("schemastore") in their settings cost ~7 ms of every start.
  plugins.schemastore = {
    enable = true;
    json.enable = false;
    yaml.enable = false;
  };
  lsp.servers.jsonls.config.before_init = lib.nixvim.mkRaw ''
    function(_, config)
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
        json = { schemas = require("schemastore").json.schemas(), validate = { enable = true } },
      })
    end
  '';
  lsp.servers.yamlls.config.before_init = lib.nixvim.mkRaw ''
    function(_, config)
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, {
        yaml = {
          schemaStore = { enable = false, url = "" },
          schemas = require("schemastore").yaml.schemas(),
        },
      })
    end
  '';

  extraPackages = with pkgs; [
    # used by the language servers above
    ansible-lint
    go
    shellcheck
  ];
}
