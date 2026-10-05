{
  lib,
  pkgs,
  package,
  target ? import ./target.nix { inherit pkgs; },
  crossPackage ? null,
  binaryPathOverride ? null,
  skipPostInstall ? false,
  skipPostFixup ? false,
}:
pkgs.callPackage ./native-binary.nix {
  inherit
    lib
    package
    target
    crossPackage
    binaryPathOverride
    skipPostInstall
    skipPostFixup
    ;
}
