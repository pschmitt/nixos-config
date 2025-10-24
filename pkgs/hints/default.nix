{
  lib,
  python3,
  fetchFromGitHub,
  wrapGAppsHook4,
  gobject-introspection,
  gtk3,
  gtk-layer-shell,
  grim,
}:

python3.pkgs.buildPythonApplication {
  pname = "hints";
  version = "unstable-2025-09-27";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "AlfredoSequeida";
    repo = "hints";
    rev = "e5739a5d1b3603935ad463338fa8ef32d55f3f55";
    hash = "sha256-02SWUH+HXiYwKGrGIu5T1W7mKtEMLjJvi8VOm+APJ5o=";
  };

  preBuild = ''
    export HOME="$out"
    export HINTS_EXPECTED_BIN_DIR="$out/bin"
  '';

  nativeBuildInputs = [
    wrapGAppsHook4
    gobject-introspection
  ];

  postFixup = ''
    for b in "$out/bin/hints" "$out/bin/hintsd"
    do
      wrapProgram "$b" --prefix PATH : ${lib.makeBinPath [ grim ]}
    done
  '';

  buildInputs = [
    gtk3
    gtk-layer-shell
  ];

  propagatedBuildInputs = with python3.pkgs; [
    pygobject3
    pillow
    pyscreenshot
    opencv4
    evdev
    dbus-python
  ];

  # Importing 'hints' can pull GI; leave empty to avoid headless import flakiness during build.
  pythonImportsCheck = [ ];

  meta = with lib; {
    description = "Keyboard-driven GUI navigation via on-screen hints";
    homepage = "https://github.com/AlfredoSequeida/hints";
    license = licenses.gpl3Only;
    maintainers = [ maintainers.pschmitt ];
    mainProgram = "hints";
    platforms = platforms.linux;
  };
}
