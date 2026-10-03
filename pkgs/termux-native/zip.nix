{
  lib,
  llvm,
  package,
  runCommand,
}:
let
  binaries = [
    "zip"
    "zipcloak"
    "zipnote"
    "zipsplit"
  ];
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
      files = map (binary: "bin/${binary}") binaries;
      binaries = map (binary: "bin/${binary}") binaries;
    };
    meta = lib.removeAttrs package.meta [ "outputsToInstall" ] // {
      mainProgram = "zip";
    };
  }
  ''
    mkdir -p "$out/bin"
    ${lib.concatMapStringsSep "\n" (binary: ''
      cp ${unstripped}/bin/${binary} "$out/bin/${binary}"
      llvm-strip --strip-unneeded "$out/bin/${binary}"
    '') binaries}
  ''
