{
  config,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxEza = pkgs.callPackage ../../pkgs/termux-native/eza.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.pkgsCross.aarch64-android-prebuilt.eza;
  };
in
{
  home.packages = [ (if termuxMode then termuxEza else pkgs.eza) ];
}
