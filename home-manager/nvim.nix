{ inputs, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    package = inputs.neovim-nightly.packages.${pkgs.system}.neovim;

    extraPackages = with pkgs; [
      # vimPlugins.nvim-treesitter.withAllGrammars
      shellcheck
      shfmt

      # nix
      nil
      nixpkgs-fmt

      luajit

      imagemagick # for image.nvim

      # lsp
      ruff-lsp
    ];

    viAlias = false;
    vimAlias = true;

    extraLuaPackages = ps: [ ps.magick ];
  };
}
