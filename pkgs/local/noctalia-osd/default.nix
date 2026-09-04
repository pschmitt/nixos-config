{ lib, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "noctalia-osd";
  version = "1.7.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./plugin.toml
      ./panel.luau
      ./README.md
      ./translations
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/share/noctalia-plugins/osd
    mkdir -p "$dest"

    cp plugin.toml panel.luau README.md "$dest"/
    cp -r translations "$dest"/

    runHook postInstall
  '';

  meta = {
    description = "Ad-hoc custom OSD toast for Noctalia, triggered via CLI/IPC with a JSON payload";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
  };
}
