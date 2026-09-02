# Overlays a custom SyncshellWidget.qml onto the upstream syncshell-dms
# plugin package, swapping the generic Material Symbol status glyph for
# Syncthing's own bundled status icons (assets/status-*.svg).
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

    runHook postInstall
  '';

  meta = {
    description = "syncshell-dms with the DankBar pill re-themed to Syncthing's own status icons";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
