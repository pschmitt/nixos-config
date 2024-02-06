{ inputs, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    package = inputs.neovim.packages.${pkgs.system}.neovim; # inputs.neovim.pkgs.neovim;

    extraPackages = with pkgs; [
      # vimPlugins.nvim-treesitter.withAllGrammars
      shellcheck
      shfmt

      # nix
      nixpkgs-fmt

      # lsp
      ruff-lsp
    ];

    viAlias = false;
    vimAlias = true;

    extraLuaPackages = ps: [ ps.magick ];
  };
}
