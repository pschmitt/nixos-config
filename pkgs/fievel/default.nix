{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  libgcc,
}:

stdenvNoCC.mkDerivation {
  pname = "fievel";
  version = "1.0.0";

  src = fetchurl {
    url = "https://github.com/MontyTheSoftwareEngineer/fievel/releases/download/1.0.0/fievel-1.0.0-linux-x64.tar.gz";
    hash = "sha256-AGVcYU/GMxAYl1oF+kXtsEiAWiccBT0+rIckivFckpU=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ libgcc ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 fievel $out/bin/fievel
    runHook postInstall
  '';

  meta = {
    description = "Keyboard-driven mouse control and key remapping for Linux";
    homepage = "https://github.com/MontyTheSoftwareEngineer/fievel";
    license = lib.licenses.mit;
    mainProgram = "fievel";
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = [ "x86_64-linux" ];
  };
}

# vim: set ft=nix et ts=2 sw=2 :
