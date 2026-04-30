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
  pname = "quickshell-overview";
  version = "unstable-2026-04-29";

  src = fetchFromGitHub {
    owner = "Shanu-Kumawat";
    repo = "quickshell-overview";
    rev = "2631a1a916d0bb0dff69b27cc781722195a74e23";
    hash = "sha256-tVhEmrffDcbQR6L9nmvJyGGIJmuQ8y/5dPNLAjOH59A=";
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

    dest=$out/share/quickshell/overview
    mkdir -p "$dest"

    cp shell.qml "$dest"/
    cp -r assets common modules services "$dest"/

    mkdir -p $out/bin

    # Qt6 QML modules live under lib/qt-6/qml
    localQmlPaths="${
      lib.makeSearchPath "lib/qt-6/qml" [
        qt6Packages.qt5compat
        qt6Packages.qtdeclarative
      ]
    }"

    # Main daemon wrapper
    makeWrapper ${quickshell}/bin/quickshell $out/bin/quickshell-overview \
      --suffix QML_IMPORT_PATH : "$localQmlPaths" \
      --suffix QML2_IMPORT_PATH : "$localQmlPaths" \
      --add-flags "-p $dest"

    # IPC convenience wrapper
    cat > $out/bin/quickshell-overview-ipc <<EOF
    #!/usr/bin/env bash
    set -euo pipefail

    usage() {
      cat <<USAGE
    Usage: quickshell-overview-ipc

    Toggle the quickshell overview UI via quickshell ipc.

    Examples:
      quickshell-overview-ipc
    USAGE
    }

    if [ "\${"1:-"}" = "-h" ] || [ "\${"1:-"}" = "--help" ]
    then
      usage
      exit 0
    fi

    if [ "\$#" -gt 0 ]
    then
      echo "Error: too many arguments" >&2
      usage >&2
      exit 2
    fi

    config_path="$dest"

    exec ${quickshell}/bin/quickshell ipc \
      -p "\$config_path" \
      call overview toggle
    EOF

    chmod +x $out/bin/quickshell-overview-ipc
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version"
      "branch"
      "--version-regex"
      "(?:0-)?(unstable-[0-9]{4}-[0-9]{2}-[0-9]{2})"
    ];
  };

  meta = with lib; {
    description = "Quickshell overview module for Hyprland";
    homepage = "https://github.com/Shanu-Kumawat/quickshell-overview";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
})
