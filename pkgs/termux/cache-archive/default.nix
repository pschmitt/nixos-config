{
  lib,
  stdenvNoCC,
  archive,
  archiveName,
}:

stdenvNoCC.mkDerivation {
  pname = "termux-${lib.removeSuffix ".tar.gz" archiveName}";
  version = "1";
  src = archive;
  dontUnpack = true;
  allowedReferences = [ ];

  installPhase = ''
    runHook preInstall
    install -Dm0444 "$src" "$out/share/termux/${archiveName}"
    runHook postInstall
  '';

  meta = {
    description = "Reference-free Nix cache wrapper for a prepared Termux archive";
    platforms = lib.platforms.linux;
  };
}
