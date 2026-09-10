{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "dms-ha-ai-usage";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./plugin.json
      ./HaAiUsageWidget.qml
      ./HaAiUsageSettings.qml
      ./assets
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/share/dms-plugins/ha-ai-usage
    mkdir -p "$dest"/assets
    cp plugin.json "$dest"/
    cp HaAiUsageWidget.qml "$dest"/
    cp HaAiUsageSettings.qml "$dest"/
    cp assets/*.svg "$dest"/assets/

    runHook postInstall
  '';

  meta = {
    description = "Home Assistant AI usage quota widget for DankMaterialShell, ported from Noctalia's pschmitt/ha-ai-usage plugin";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
  };
}
