{
  config,
  inputs,
  pkgs,
  ...
}:
let
  # The stable (fully wrapped) nvim from Home Manager.
  nvimStable = config.programs.neovim.finalPackage;

  # The unwrapped nightly binary from your flake input.
  nvimNightly = inputs.neovim-nightly.packages.${pkgs.stdenv.hostPlatform.system}.neovim;

  # A second script that copies stable's wrapper environment,
  # but calls the nightly binary.
  nvimNightlyWrapped =
    pkgs.runCommand "nvim-nightly-from-stable"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.gnused
          pkgs.makeWrapper
        ];
      }
      ''
        mkdir -p $out/bin
        cp ${nvimStable}/bin/nvim $out/bin/nvim-nightly

        sed -i "s|${config.programs.neovim.package}|${nvimNightly}|" \
          $out/bin/nvim-nightly
      '';

in
{
  programs.neovim = {
    enable = true;
    # package = inputs.neovim-nightly.packages.${pkgs.stdenv.hostPlatform.system}.neovim;

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

    viAlias = false;
    vimAlias = true;

    extraLuaPackages = ps: [ ps.magick ];
  };

  home.packages = [ nvimNightlyWrapped ];
}
