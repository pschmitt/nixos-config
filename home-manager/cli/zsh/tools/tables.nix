{ pkgs, ... }:
{
  # Table helpers the tsv::/gitlab:: functions pipe through. zinit hosts get
  # the uv-script versions from yadm's ~/bin instead.
  home.packages = [
    pkgs.pycolumn
    pkgs.zebra
  ];
}
