{
  lib,
  pkgs,
  package,
  crossPackage ? null,
  skipPostInstall ? false,
  skipPostFixup ? false,
}:
pkgs.callPackage ./native-binary.nix {
  inherit
    lib
    package
    crossPackage
    skipPostInstall
    skipPostFixup
    ;
}
