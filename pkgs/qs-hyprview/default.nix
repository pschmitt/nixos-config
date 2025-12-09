{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  qt6Packages,
  quickshell,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "qs-hyprview";
  version = "0-unstable-2025-12-07";

  src = fetchFromGitHub {
    owner = "dom0";
    repo = "qs-hyprview";
    rev = "8354f99a26ca6e88b105bf86b886d6b1399deed7"; # TODO: pin a real commit
    hash = "sha256-7nmHhI5pkHq1Ln76TatqhAB6XPQ52Zut1gc9tyLBVUQ=";
  };

  dontConfigure = true;
  dontBuild = true;
  dontWrapQtApps = true;

  nativeBuildInputs = [
    makeWrapper
  ];

  propagatedBuildInputs = [
    quickshell
    qt6Packages.qt5compat
    qt6Packages.qtdeclarative
  ];

  installPhase = ''
    runHook preInstall

    dest=$out/share/quickshell/qs-hyprview
    mkdir -p "$dest"

    cp shell.qml "$dest"/
    cp -r modules layouts "$dest"/

    mkdir -p $out/bin

    # Qt6 QML modules live under lib/qt-6/qml
    localQmlPaths="${qt6Packages.qt5compat}/lib/qt-6/qml"

    # Main daemon wrapper
    makeWrapper ${quickshell}/bin/quickshell $out/bin/qs-hyprview \
      --suffix QML_IMPORT_PATH : "$localQmlPaths" \
      --suffix QML2_IMPORT_PATH : "$localQmlPaths" \
      --add-flags "-p $dest"

    # IPC convenience wrapper
    cat > $out/bin/qs-hyprview-ipc <<EOF
    #!/usr/bin/env bash
    set -euo pipefail

    usage() {
      cat <<USAGE
    Usage: qs-hyprview-ipc [LAYOUT]

    Toggle the qs-hyprview expose UI via quickshell ipc.

    If LAYOUT is omitted, "masonry" is used.

    Examples:
      qs-hyprview-ipc
      qs-hyprview-ipc smartgrid
    USAGE
    }

    layout="masonry"

    if [ "\${"1:-"}" = "-h" ] || [ "\${"1:-"}" = "--help" ]
    then
      usage
      exit 0
    fi

    if [ "\$#" -gt 1 ]
    then
      echo "Error: too many arguments" >&2
      usage >&2
      exit 2
    fi

    if [ "\$#" -eq 1 ]
    then
      layout="\$1"
    fi

    config_path="$dest"

    exec ${quickshell}/bin/quickshell ipc \
      -p "\$config_path" \
      call expose toggle "\$layout"
    EOF

    chmod +x $out/bin/qs-hyprview-ipc
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version"
      "branch"
    ];
  };

  meta = with lib; {
    description = "QML-based window switcher/Exposé for Hyprland powered by Quickshell";
    homepage = "https://github.com/dom0/qs-hyprview";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
})
