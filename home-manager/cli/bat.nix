{
  config,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxBat = pkgs.callPackage ../../pkgs/termux-native/bat.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.pkgsCross.aarch64-android-prebuilt.bat;
  };
in
{
  home.packages = [ (if termuxMode then termuxBat else pkgs.bat) ];
}
