{
  lib,
  llvm,
  pkgs,
  package,
  binary,
  crossPackage ? null,
  runCommand,
}:
let
  packageName = lib.getName package;
  androidPackages = pkgs.pkgsCross.aarch64-android-prebuilt;
  androidPackage =
    if crossPackage != null then
      crossPackage
    else if (package.stdenv.hostPlatform.isAndroid or false) then
      package
    else if builtins.hasAttr packageName androidPackages then
      androidPackages.${packageName}
    else
      throw ''
        ${packageName} has no package in Nixpkgs' aarch64-android-prebuilt cross set.
        Add an explicit Android build or use a Termux package instead.
      '';
  checkedAndroidPackage =
    if androidPackage.stdenv.hostPlatform.isAndroid or false then
      androidPackage
    else
      throw "${packageName} cross package is not built for Android/Bionic";
  unstripped = checkedAndroidPackage.overrideAttrs (_: {
    doCheck = false;
    doInstallCheck = false;
    dontStrip = true;
    postFixup = "";
  });
  runtimeRoots = [
    unstripped
  ]
  ++ map lib.getLib ((unstripped.buildInputs or [ ]) ++ (unstripped.propagatedBuildInputs or [ ]));
  runtimeClosure = pkgs.closureInfo {
    rootPaths = lib.unique runtimeRoots;
  };
in
runCommand "${lib.getName package}-termux"
  {
    nativeBuildInputs = [ llvm ];
    allowedReferences = [ ];
    passthru.termuxNative = {
      abi = "android-bionic";
      files = [ binary ];
      binaries = [ binary ];
      runtimeClosure = "${runtimeClosure}/store-paths";
    };
    meta = lib.removeAttrs checkedAndroidPackage.meta [ "outputsToInstall" ] // {
      mainProgram = builtins.baseNameOf binary;
    };
  }
  ''
    mkdir -p "$out/$(dirname ${lib.escapeShellArg binary})"
    cp ${unstripped}/${binary} "$out/${binary}"
    llvm-strip --strip-unneeded "$out/${binary}"
  ''
