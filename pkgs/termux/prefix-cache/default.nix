{
  lib,
  stdenvNoCC,
  unzip,
  gnutar,
  gzip,
  archive,
}:

stdenvNoCC.mkDerivation {
  pname = "termux-prefix-cache";
  version = "1";

  src = archive;
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  nativeBuildInputs = [
    gnutar
    gzip
    unzip
  ];
  allowedReferences = [ ];

  installPhase = ''
    runHook preInstall
    bash ${./prepare-prefix.sh} "$src" "$out"
    runHook postInstall
  '';

  meta = {
    description = "Reference-free Termux prefix archive from the official bootstrap generator";
    platforms = lib.platforms.linux;
  };
}
