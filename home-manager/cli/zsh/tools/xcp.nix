{
  config,
  inputs,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxPackageSet = import ../../../../pkgs/termux/native/package-set.nix {
    inherit inputs pkgs;
  };
in
{
  # Clipboard helper (tmux copy-command, clipper, zsh functions). zinit
  # hosts get the script from yadm's ~/bin instead.
  home.packages = [ (if termuxMode then termuxPackageSet.termuxPackages.xcp else pkgs.xcp) ];
}
