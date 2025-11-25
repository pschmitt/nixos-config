{ pkgs, ... }:
{
  home.packages = with pkgs; [
    alejandra
    cachix
    niv
    nix-init
    nixfmt-rfc-style
    nixos-anywhere
    nixos-generators
    nixpkgs-fmt
    nvd
    statix
  ];
}
