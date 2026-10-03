{
  lib,
  llvm,
  package,
  runCommand,
}:
import ./native-binary.nix {
  inherit
    lib
    llvm
    package
    runCommand
    ;
  binary = "bin/eza";
}
