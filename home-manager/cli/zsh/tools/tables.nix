{
  config,
  inputs,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  inherit (import ../../../../pkgs/termux/native/package-set.nix { inherit inputs pkgs; })
    termuxPackages
    ;
in
{
  # Table helpers the tsv::/gitlab:: functions pipe through. zinit hosts get
  # the uv-script versions from yadm's ~/bin instead.
  home.packages =
    if termuxMode then
      [
        termuxPackages.pycolumn
        termuxPackages.tsvtool
        termuxPackages.zebra
      ]
    else
      [
        inputs.tsvtool.packages.${pkgs.stdenv.hostPlatform.system}.default
        pkgs.pycolumn
        pkgs.zebra
      ];
}
