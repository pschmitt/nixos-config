# Overlays a custom SyncshellWidget.qml + colored status badges onto the
# upstream syncshell-dms plugin package, swapping the generic Material
# Symbol status glyph for the Syncthing logo with a synced (green check)
# / syncing (blue) / paused (gray) / issue (red) badge. Also extends the
# daemon + API client (upstream is read-only) with Rescan All / Pause
# All / Resume All, driven from the popout footer and a right-click
# pause/resume toggle.
{
  lib,
  stdenvNoCC,
  stdenv,
  inputs,
}:

let
  upstream = inputs.syncshell-dms.packages.${stdenv.hostPlatform.system}.default;
in
stdenvNoCC.mkDerivation {
  pname = "syncshell-dms-dank-logo";
  inherit (upstream) version;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    dest=$out/share/dms-plugins/syncshell
    mkdir -p "$dest"
    cp -r ${upstream}/share/dms-plugins/syncshell/. "$dest"/
    chmod -R u+w "$dest"
    cp ${./SyncshellWidget.qml} "$dest"/SyncshellWidget.qml
    cp ${./SyncshellDaemon.qml} "$dest"/SyncshellDaemon.qml
    cp ${./models/SyncthingApi.js} "$dest"/models/SyncthingApi.js
    cp ${./assets}/*.svg "$dest"/assets/

    runHook postInstall
  '';

  meta = {
    description = "syncshell-dms re-themed with Syncthing's own status icons, plus Rescan/Pause/Resume All";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
