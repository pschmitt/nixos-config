{
  lib,
  llvm,
  package,
  binary,
  runCommand,
}:
let
  unstripped = package.overrideAttrs (_: {
    doCheck = false;
    doInstallCheck = false;
    dontStrip = true;
    postFixup = "";
  });
in
runCommand "${lib.getName package}-termux"
  {
    nativeBuildInputs = [ llvm ];
    allowedReferences = [ ];
    passthru.termuxNative = {
      files = [ binary ];
      binaries = [ binary ];
    };
    meta = lib.removeAttrs package.meta [ "outputsToInstall" ] // {
      mainProgram = builtins.baseNameOf binary;
    };
  }
  ''
    mkdir -p "$out/$(dirname ${lib.escapeShellArg binary})"
    cp ${unstripped}/${binary} "$out/${binary}"
    llvm-strip --strip-unneeded "$out/${binary}"
  ''
