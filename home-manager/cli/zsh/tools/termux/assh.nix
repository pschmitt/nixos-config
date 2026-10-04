{
  config,
  inputs,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxPackageSet = import ../../../../../pkgs/termux-native/package-set.nix {
    inherit inputs pkgs;
  };
  inherit (termuxPackageSet) termuxPackages;
in
{
  home.packages = [ (if termuxMode then termuxPackages.assh else pkgs.assh) ];
}
