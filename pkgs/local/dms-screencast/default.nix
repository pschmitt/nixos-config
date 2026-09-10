{
  lib,
  stdenvNoCC,
  screencast-state,
}:

stdenvNoCC.mkDerivation {
  pname = "dms-screencast";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./plugin.json
      ./ScreencastWidget.qml
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/share/dms-plugins/screencast
    mkdir -p "$dest"
    cp plugin.json "$dest"/
    substitute ScreencastWidget.qml "$dest"/ScreencastWidget.qml \
      --subst-var-by screencastState ${screencast-state}/bin/screencast-state

    runHook postInstall
  '';

  meta = {
    description = "Screencast REC indicator for DankMaterialShell, ported from Noctalia's pschmitt/screencast plugin";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
  };
}
