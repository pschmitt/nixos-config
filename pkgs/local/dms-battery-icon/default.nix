{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "dms-battery-icon";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./plugin.json
      ./BatteryIconWidget.qml
      ./BatteryIconSettings.qml
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/share/dms-plugins/battery-icon
    mkdir -p "$dest"
    cp plugin.json "$dest"/
    cp BatteryIconWidget.qml "$dest"/
    cp BatteryIconSettings.qml "$dest"/

    runHook postInstall
  '';

  meta = {
    description = "Android-style battery pill widget for DankMaterialShell, ported from Noctalia's pschmitt/battery-icon plugin";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
  };
}
