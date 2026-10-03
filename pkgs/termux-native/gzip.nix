{
  lib,
  llvm,
  package,
  runCommand,
}:
let
  binaries = [
    "gzip"
    "gunzip"
    "uncompress"
    "zcat"
  ];
  scripts = [
    "gzexe"
    "zcmp"
    "zdiff"
    "zegrep"
    "zfgrep"
    "zforce"
    "zgrep"
    "zless"
    "zmore"
    "znew"
  ];
  binaryFiles = map (binary: "bin/${binary}") binaries;
  scriptFiles = map (script: "bin/${script}") scripts;
  files = binaryFiles ++ scriptFiles;
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
      inherit files;
      binaries = binaryFiles;
      scripts = scriptFiles;
    };
    meta = lib.removeAttrs package.meta [ "outputsToInstall" ] // {
      mainProgram = "gzip";
    };
  }
  ''
    mkdir -p "$out/bin"
    cp ${unstripped}/bin/gzip "$out/bin/gzip"
    llvm-strip --strip-unneeded "$out/bin/gzip"
    ln -s gzip "$out/bin/gunzip"
    ln -s gzip "$out/bin/uncompress"
    ln -s gzip "$out/bin/zcat"
    ${lib.concatMapStringsSep "\n" (script: ''
      cp ${unstripped}/bin/${script} "$out/bin/${script}"
      sed -i \
        -e '1s|^#!.*|#!/data/data/com.termux/files/usr/bin/sh|' \
        -e 's|${unstripped}|$TERMUX_GENERATION/native/${lib.getName package}-termux|g' \
        "$out/bin/${script}"
    '') scripts}
  ''
