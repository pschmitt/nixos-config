{
  lib,
  python3,
  fetchFromGitHub,
  pkgs,
}:

let
  launcher = pkgs.writeTextFile {
    name = "clipcascade-launcher";
    executable = true;
    destination = "/bin/clipcascade";
    text = ''
      #!${python3.interpreter}

      from clipcascade.main import Main

      if __name__ == "__main__":
          Main()
    '';
  };

  giTypelibs = lib.makeSearchPath "lib/girepository-1.0" [
    pkgs.gdk-pixbuf
    pkgs.glib
    pkgs.gobject-introspection
    pkgs.gtk3
    pkgs.libayatana-appindicator
  ];
in
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

  patches = [ ./fix-paths.patch ];

  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.wrapGAppsHook3
  ];

  buildInputs = [
    pkgs.gsettings-desktop-schemas
    pkgs.gobject-introspection
    pkgs.gdk-pixbuf
    pkgs.gtk3
    pkgs.libayatana-appindicator
    pkgs.shared-mime-info
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
    tkinter
    websocket-client
    xxhash
  ];

  installPhase = ''
    runHook preInstall

    sitePackages="$out/${python3.sitePackages}"
    install -d "$sitePackages/clipcascade" "$out/bin"

    cp -r cli clipboard core gui interfaces p2p stomp_ws utils main.py "$sitePackages/clipcascade"

    install -Dm755 ${launcher}/bin/clipcascade "$out/bin/clipcascade"

    runHook postInstall
  '';

  preFixup = ''
    makeWrapperArgs+=(
      --prefix PYTHONPATH : "$out/${python3.sitePackages}:$out/${python3.sitePackages}/clipcascade"
      --prefix PATH : "${
        lib.makeBinPath [
          pkgs.wl-clipboard
          pkgs.xclip
        ]
      }"
      --prefix GI_TYPELIB_PATH : "${giTypelibs}"
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
