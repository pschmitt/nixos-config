{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "noctalia-screencast";
  version = "0.2.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./plugin.toml
      ./service.luau
      ./bar.luau
      ./translations
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/share/noctalia-plugins/screencast
    mkdir -p "$dest"

    cp plugin.toml service.luau bar.luau "$dest"/
    cp -r translations "$dest"/

    runHook postInstall
  '';

  meta = {
    description = "Red-dot REC bar indicator for Noctalia while screensharing, ported from the Waybar custom/screencast module";
    license = lib.licenses.gpl3Only;
    maintainers = [ lib.maintainers.pschmitt ];
    platforms = lib.platforms.linux;
  };
}
