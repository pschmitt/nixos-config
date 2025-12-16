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
      codespell
      tree-sitter

      # for random plugins that need to compile native extensions
      # eg: luasnip
      gcc

      # vimPlugins.nvim-treesitter.withAllGrammars
      shellcheck
      shfmt

      # nix
      nil
      nixpkgs-fmt

      # jssonnet
      jsonnet-language-server

      # markdown
      marksmanWrapped

      # lua
      luajit
      stylua

      nodejs # for copilot

      imagemagick # for image.nvim, snacks.images etc.
    ];

    viAlias = false;
    vimAlias = true;

    extraLuaPackages = ps: [ ps.magick ];
  };

  home.packages = [ nvimNightlyWrapped ];
}
