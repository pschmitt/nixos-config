{
  inputs,
  pkgs,
  ...
}:
let
  # The unwrapped nightly binary from your flake input.
  nvimNightly = inputs.neovim-nightly.packages.${pkgs.stdenv.hostPlatform.system}.neovim;

  # Define common configuration to avoid duplication.
  commonConfig = {
    withRuby = false;
    withPython3 = false;

    extraPackages = with pkgs; [
      # vimPlugins.nvim-treesitter.withAllGrammars
      codespell
      tree-sitter

      # for random plugins that need to compile native extensions
      # eg: luasnip
      gcc

      # for copilot
      nodejs

      # for image.nvim, snacks.images etc.
      ghostscript
      imagemagick

      # ansible
      ansible-lint
      # ansible-language-server

      # docker
      docker-language-server
      dockerfile-language-server
      hadolint

      # golang
      go
      gopls

      # jsonnet
      jsonnet-language-server

      # lua
      luajit
      lua-language-server
      stylua

      # markdown
      marksman
      markdown-toc
      markdownlint-cli2

      # nix
      nil
      nixpkgs-fmt

      # python
      pyright
      ruff

      # shell
      bash-language-server
      shellcheck
      shfmt

      # tofu/terraform
      terraform-ls

      # toml
      taplo
    ];

    extraLuaPackages = ps: [ ps.magick ];
  };

  # Prepare the configuration for the wrapper.
  neovimConfig = pkgs.neovimUtils.makeNeovimConfig {
    inherit (commonConfig) withPython3 withRuby extraLuaPackages;
    customLuaRC = ''
      dofile(vim.fn.stdpath("config") .. "/init.lua##class.notnixos")
    '';
  };

  # Wrap the nightly binary with the same environment as stable.
  nvimNightlyWrapped = pkgs.wrapNeovimUnstable nvimNightly (
    neovimConfig
    // {
      wrapperArgs = neovimConfig.wrapperArgs ++ [
        "--prefix"
        "PATH"
        ":"
        (pkgs.lib.makeBinPath commonConfig.extraPackages)
      ];
    }
  );
in
{
  programs.neovim = commonConfig // {
    enable = true;
    viAlias = false;
    vimAlias = true;

    # DIRTYFIX load our regular init.lua (yadm-managed)
    initLua = ''
      dofile(vim.fn.stdpath("config") .. "/init.lua##class.notnixos")
    '';
  };

  # Provide the nvim-nightly command.
  home.packages = [
    (pkgs.runCommand "nvim-nightly" { } ''
      mkdir -p $out/bin
      ln -s ${nvimNightlyWrapped}/bin/nvim $out/bin/nvim-nightly
    '')
  ];
}
