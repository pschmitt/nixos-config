{
  lib,
  llvm,
  package,
  binary,
  runCommand,
}:
let
  targetPlatform = package.stdenv.hostPlatform or { };
  androidPackage =
    if targetPlatform.isAndroid or false then
      package
    else
      throw ''
        ${lib.getName package} is not built for Android/Bionic.
        Select its Android cross package or rebuild it with an Android toolchain;
        removing RPATHs cannot convert a glibc binary into a Termux binary.
      '';
  unstripped = androidPackage.overrideAttrs (_: {
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
      abi = "android-bionic";
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
