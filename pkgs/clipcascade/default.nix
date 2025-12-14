{
  lib,
  python3,
  fetchFromGitHub,
  pkgs,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "clipcascade";
  version = "3.1.0";
  format = "other";

  src = fetchFromGitHub {
    owner = "Sathvik-Rao";
    repo = "ClipCascade";
    rev = version;
    hash = "sha256-+csAEPCdPHxWz7gp4ES4r5bOnVUKDw3oo8lt4MXqKyo=";
  };

  sourceRoot = "source/ClipCascade_Desktop/src";

  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.wrapGAppsHook3
  ];

  buildInputs = [
    pkgs.gobject-introspection
    pkgs.gtk3
    pkgs.libayatana-appindicator
  ];

  propagatedBuildInputs = with python3.pkgs; [
    aiortc
    beautifulsoup4
    pillow
    plyer
    pycryptodome
    pyfiglet
    pygobject3
    pystray
    requests
    websocket-client
    xxhash
    tkinter
  ];

  installPhase = ''
    runHook preInstall

    sitePackages="$out/${python3.sitePackages}"
    install -d "$sitePackages/clipcascade" "$out/bin"

    cp -r cli clipboard core gui interfaces p2p stomp_ws utils main.py "$sitePackages/clipcascade"

    cat > $out/bin/clipcascade <<EOF
    #!${python3.interpreter}
    import os
    import sys

    sys.path.insert(0, "$sitePackages")
    sys.path.insert(0, os.path.join("$sitePackages", "clipcascade"))

    from clipcascade.main import Main

    if __name__ == "__main__":
        Main()
    EOF
    chmod +x $out/bin/clipcascade

    runHook postInstall
  '';

  postPatch = ''
        ${python3.interpreter} <<'PY'
    import os
    import pathlib

    path = pathlib.Path("core/constants.py")
    text = path.read_text()

    needle = """    else:
            if getattr(sys, "frozen", False):  # Running as a PyInstaller executable
                return os.path.dirname(sys.executable)
            else:  # Running as a regular Python script
                running_dir = os.path.dirname(os.path.abspath(__file__))
                parent_dir = os.path.dirname(running_dir)  # Go one folder up
                return parent_dir
    """

    replacement = """    elif PLATFORM.startswith(LINUX):
            data_dir = os.environ.get(
                "XDG_STATE_HOME", os.path.join(get_user_home_directory(), ".local", "state")
            )
            app_dir = os.path.join(data_dir, "clipcascade")
            os.makedirs(app_dir, exist_ok=True)
            return app_dir
        else:
            if getattr(sys, "frozen", False):  # Running as a PyInstaller executable
                return os.path.dirname(sys.executable)
            else:  # Running as a regular Python script
                running_dir = os.path.dirname(os.path.abspath(__file__))
                parent_dir = os.path.dirname(running_dir)  # Go one folder up
                return parent_dir
    """

    if needle not in text:
        raise RuntimeError("Expected get_program_files_directory() body not found")

    path.write_text(text.replace(needle, replacement))
    PY
  '';

  preFixup = ''
    sitePackages="$out/${python3.sitePackages}"
    giTypelibs="${
      lib.makeSearchPath "lib/girepository-1.0" [
        pkgs.gobject-introspection
        pkgs.gtk3
        pkgs.gdk-pixbuf
        pkgs.libayatana-appindicator
      ]
    }"
    xdgDataDirs="${
      lib.makeSearchPath "share" [
        pkgs.gtk3
        pkgs.libayatana-appindicator
        pkgs.shared-mime-info
        pkgs.gsettings-desktop-schemas
      ]
    }"
    makeWrapperArgs+=(
      --prefix PYTHONPATH : "$PYTHONPATH:$sitePackages"
      --prefix PATH : ${
        lib.makeBinPath [
          pkgs.wl-clipboard
          pkgs.xclip
        ]
      }
      --prefix GI_TYPELIB_PATH : "$GI_TYPELIB_PATH:$giTypelibs"
      --prefix XDG_DATA_DIRS : "$XDG_DATA_DIRS:$xdgDataDirs"
    )
  '';

  doCheck = false;

  meta = with lib; {
    description = "Clipboard syncing utility for desktop platforms";
    homepage = "https://github.com/Sathvik-Rao/ClipCascade";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "clipcascade";
    platforms = platforms.linux;
  };
}
