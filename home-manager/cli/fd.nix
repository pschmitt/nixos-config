{
  config,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxFd = pkgs.callPackage ../../pkgs/termux-native/fd.nix {
    llvm = pkgs.llvmPackages.llvm;
    package = pkgs.pkgsCross.aarch64-android-prebuilt.fd;
  };
in
{
  home.packages = [ (if termuxMode then termuxFd else pkgs.fd) ];
}
