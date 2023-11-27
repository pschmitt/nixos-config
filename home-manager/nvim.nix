{ inputs, lib, config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    extraPackages = with pkgs; [
      # vimPlugins.nvim-treesitter.withAllGrammars
      shellcheck
      shfmt

      # nix
      nixpkgs-fmt
    ];

    viAlias = false;
    vimAlias = true;
  };
}
