{
  lib,
  pkgs,
  package,
  target ? import ./target.nix { inherit pkgs; },
  crossPackage ? null,
  binaryPathOverride ? null,
  binaryPaths ? null,
  extraFiles ? [ ],
  scripts ? [ ],
  trees ? [ ],
  aptPackages ? [ ],
  aptLibraries ? [ ],
  runtimeInputs ? [ ],
  runtimeLibraries ? [ ],
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
    binaryPaths
    extraFiles
    scripts
    trees
    aptPackages
    aptLibraries
    runtimeInputs
    runtimeLibraries
    skipPostInstall
    skipPostFixup
    ;
}
