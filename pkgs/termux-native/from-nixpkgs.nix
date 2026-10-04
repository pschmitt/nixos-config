{
  lib,
  pkgs,
  package,
  crossPackage ? null,
}:
pkgs.callPackage ./native-binary.nix {
  inherit lib package crossPackage;
  llvm = pkgs.llvmPackages.llvm;
}
