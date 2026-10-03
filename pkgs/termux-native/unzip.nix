{
  bzip2,
  lib,
  llvm,
  package,
  runCommand,
}:
let
  binaries = [
    "funzip"
    "unzip"
    "unzipsfx"
    "zipinfo"
  ];
  scripts = [ "zipgrep" ];
  binaryFiles = map (binary: "bin/${binary}") binaries;
  scriptFiles = map (script: "bin/${script}") scripts;
  files = binaryFiles ++ scriptFiles ++ [ "lib/libbz2.so" ];
  patched = package.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace unix/configure \
        --replace-fail \
        'echo "int main(){ char k; memset(&k,0,0); return 0; }" > conftest.c' \
        'printf "%s\\n" "#include <string.h>" "int main(){ char k; memset(&k,0,0); return 0; }" > conftest.c'
    '';
  });
  unstripped = patched.overrideAttrs (_: {
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
      inherit
        files
        ;
      binaries = binaryFiles;
      scripts = scriptFiles;
    };
    meta = lib.removeAttrs package.meta [ "outputsToInstall" ] // {
      mainProgram = "unzip";
    };
  }
  ''
      mkdir -p "$out/bin" "$out/lib"
      ${lib.concatMapStringsSep "\n" (binary: ''
        cp ${unstripped}/bin/${binary} "$out/bin/${binary}"
        llvm-strip --strip-unneeded "$out/bin/${binary}"
      '') binaries}
      cp ${unstripped}/bin/zipgrep "$out/bin/zipgrep"
      sed -i '1s|^#!.*|#!/data/data/com.termux/files/usr/bin/sh|' "$out/bin/zipgrep"
    cp -L ${bzip2.out}/lib/libbz2.so "$out/lib/libbz2.so"
  ''
