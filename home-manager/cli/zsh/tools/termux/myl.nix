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
  inherit (termuxPackageSet.termuxPackages) myl;
in
{
  home.packages = [
    (if termuxMode then myl else inputs.myl.packages.${pkgs.stdenv.hostPlatform.system}.myl)
  ];
}
