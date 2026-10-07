{
  lib,
  pkgs,
  package,
  target ? import ./target.nix { inherit pkgs; },
  binaryPathOverride ? null,
  binaryPaths ? null,
  extraFiles ? [ ],
  scripts ? [ ],
  trees ? [ ],
  aptPackages ? [ ],
  aptLibraries ? [ ],
  runtimeInputs ? [ ],
  runtimeLibraries ? [ ],
  crossPackage ? null,
  skipPostInstall ? false,
  skipPostFixup ? false,
  runCommand,
}:
let
  packageName = lib.getName package;
  mainProgram = (package.meta or { }).mainProgram or null;
  binaryPath =
    if binaryPathOverride != null then
      binaryPathOverride
    else if mainProgram != null then
      "bin/${mainProgram}"
    else
      throw "${packageName} has no meta.mainProgram; set binary explicitly";
  exportedBinaries = if binaryPaths == null then [ binaryPath ] else binaryPaths;
  exportedFiles = lib.unique (exportedBinaries ++ scripts ++ extraFiles);
  androidPackages = target.pkgs.extend (
    _final: prev: {
      # Android's NDK linker is lld, but Nixpkgs' LLVM detection misses it in
      # this cross set. ncurses' version map names symbols it doesn't define,
      # which lld rejects without this flag.
      ncurses = prev.ncurses.overrideAttrs (old: {
        configureFlags = (old.configureFlags or [ ]) ++ [ "LDFLAGS=-Wl,--undefined-version" ];
      });
    }
  );
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
  targetBintools = checkedAndroidPackage.stdenv.cc.bintools;
  unstripped = checkedAndroidPackage.overrideAttrs (old: {
    doCheck = false;
    doInstallCheck = false;
    dontStrip = true;
    postInstall = if skipPostInstall then "" else (old.postInstall or "");
    postFixup = if skipPostFixup then "" else (old.postFixup or "");
  });
  runtimeRoots = [
    unstripped
  ]
  ++ map lib.getLib (
    (unstripped.buildInputs or [ ]) ++ (unstripped.propagatedBuildInputs or [ ]) ++ runtimeInputs
  );
  runtimeClosure = pkgs.closureInfo {
    rootPaths = lib.unique runtimeRoots;
  };
  copyFiles = lib.concatMapStringsSep "\n" (path: ''
    mkdir -p "$out/$(dirname ${lib.escapeShellArg path})"
    cp ${unstripped}/${path} "$out/${path}"
  '') exportedFiles;
  stripBinaries = lib.concatMapStringsSep "\n" (path: ''
    ${target.objcopy} --strip-unneeded "$out/${path}"
  '') exportedBinaries;
in
assert exportedBinaries != [ ];
assert aptLibraries == [ ] || aptPackages != [ ];
runCommand "${lib.getName package}-termux"
  {
    nativeBuildInputs = [ targetBintools ];
    allowedReferences = [ ];
    passthru.termuxNative = {
      abi = "android-bionic";
      files = exportedFiles;
      binaries = exportedBinaries;
      inherit
        scripts
        trees
        aptPackages
        aptLibraries
        runtimeLibraries
        ;
      runtimeClosure = "${runtimeClosure}/store-paths";
    };
    meta = lib.removeAttrs checkedAndroidPackage.meta [ "outputsToInstall" ] // {
      mainProgram = builtins.baseNameOf (builtins.head exportedBinaries);
    };
  }
  ''
    ${copyFiles}
    ${stripBinaries}
  ''
