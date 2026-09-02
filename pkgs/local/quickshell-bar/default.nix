{
  lib,
  stdenvNoCC,
  makeWrapper,
  qt6Packages,
  quickshell,
  glib,
  gsettings-desktop-schemas,
  wttrbar,
  timew-status,
  enableSoftKeyboard ? false,
}:

stdenvNoCC.mkDerivation {
  pname = "quickshell-bar";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./qmldir
      ./shell.qml
      ./Bar.qml
      ./BarSpacer.qml
      ./Theme.qml
      ./modules
      ./widgets
    ];
  };

  dontConfigure = true;
  dontBuild = true;
  dontWrapQtApps = true;

  nativeBuildInputs = [ makeWrapper ];

  propagatedBuildInputs = [
    quickshell
    qt6Packages.qt5compat
    qt6Packages.qtdeclarative
  ];

  installPhase = ''
    runHook preInstall

    dest=$out/share/quickshell/bar
    mkdir -p "$dest"

    cp qmldir shell.qml Bar.qml BarSpacer.qml Theme.qml "$dest"/
    cp -r modules widgets "$dest"/

    cat > "$dest"/Config.qml <<EOF
    pragma Singleton
    import QtQuick

    QtObject {
        readonly property bool enableSoftKeyboard: ${lib.boolToString enableSoftKeyboard}
    }
    EOF

    mkdir -p $out/bin

    localQmlPaths="${
      lib.makeSearchPath "lib/qt-6/qml" [
        qt6Packages.qt5compat
        qt6Packages.qtdeclarative
      ]
    }"

    makeWrapper ${quickshell}/bin/quickshell $out/bin/quickshell-bar \
      --suffix QML_IMPORT_PATH : "$localQmlPaths" \
      --suffix QML2_IMPORT_PATH : "$localQmlPaths" \
      --prefix PATH : ${
        lib.makeBinPath [
          glib
          wttrbar
          timew-status
        ]
      } \
      --suffix XDG_DATA_DIRS : "${gsettings-desktop-schemas}/share/gsettings-schemas/${gsettings-desktop-schemas.name}" \
      --add-flags "-p $dest"

    runHook postInstall
  '';

  meta = {
    description = "Custom Quickshell top bar (Waybar alternative) for Hyprland";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
