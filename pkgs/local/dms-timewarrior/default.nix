{
  lib,
  stdenvNoCC,
  timew-status,
}:

stdenvNoCC.mkDerivation {
  pname = "dms-timewarrior";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./plugin.json
      ./TimewarriorWidget.qml
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/share/dms-plugins/timewarrior
    mkdir -p "$dest"

    cp plugin.json "$dest"/
    substitute TimewarriorWidget.qml "$dest"/TimewarriorWidget.qml \
      --subst-var-by timewIsOn ${timew-status}/bin/timew-is-on \
      --subst-var-by timewTotal ${timew-status}/bin/timew-total \
      --subst-var-by timewWeekBreakdown ${timew-status}/bin/timew-week-breakdown

    runHook postInstall
  '';

  meta = {
    description = "Timewarrior tracked-time widget for DankMaterialShell, ported from the Waybar/quickshell-bar module";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
  };
}
