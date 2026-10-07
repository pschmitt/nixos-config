{
  config,
  inputs,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxPackageSet = import ../../pkgs/termux/native/package-set.nix {
    inherit inputs pkgs;
  };
  inherit (termuxPackageSet.termuxPackages) eget;
in
{
  home.packages = [ (if termuxMode then eget else pkgs.eget) ];
}
