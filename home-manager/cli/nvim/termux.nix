{
  config,
  inputs,
  lib,
  ...
}:
let
  termuxMode = config.termux.enable or false;
in
{
  imports = [
    ../../termux-options.nix
    inputs.lazyvim.homeManagerModules.default
  ];

  config = lib.mkIf termuxMode {
    programs.lazyvim = {
      enable = true;
      appName = "nvim";
      configFiles = ./config;
      installCoreDependencies = false;
      extraPackages = [ ];
      extras = {
        ai = {
          copilot-native.enable = true;
          sidekick.enable = true;
        };
        coding = {
          luasnip.enable = true;
          yanky.enable = true;
        };
        editor = {
          snacks-explorer.enable = true;
          snacks-picker.enable = true;
        };
        formatting = {
          black.enable = true;
          prettier.enable = true;
        };
        lang =
          lib.genAttrs
            [
              "ansible"
              "docker"
              "go"
              "json"
              "nix"
              "python"
              "terraform"
              "toml"
              "yaml"
            ]
            (_: {
              enable = true;
              installDependencies = false;
            });
        lsp.none-ls.enable = true;
        util = {
          dot.enable = true;
          project.enable = true;
        };
      };
    };

    # The bundle supplies the native Termux APT Neovim. Keep Home Manager's
    # generated LazyVim files and pinned plugin sources, but omit its Linux
    # Neovim wrapper and package closure.
    programs.neovim.enable = lib.mkForce false;

    termux.packages = [
      "neovim"
      "git"
      "curl"
      "fzf"
      "ripgrep"
      "fd"
      "clang"
      "gopls"
      "lua-language-server"
      "marksman"
      "ruff"
      "taplo"
      "tree-sitter"
      "nodejs"
      "ty"
    ];

    xdg.configFile =
      import ./config-files.nix {
        appName = "nvim";
        inherit lib;
      }
      // {
        "nvim/stylua.toml".source = ./config/stylua.toml;
        "nvim/lua/plugins/_lazyvim_nix_treesitter.lua" = lib.mkForce {
          text = ''
            -- Termux installs parsers into its writable app data directory.
            return {}
          '';
        };
      };
  };
}
