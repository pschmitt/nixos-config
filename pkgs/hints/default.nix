{
  lib,
  python3,
  fetchFromGitHub,
  wrapGAppsHook4,
  gobject-introspection,
  gtk3,
  gtk-layer-shell,
  grim,
  nix-update-script,
}:

python3.pkgs.buildPythonApplication {
  pname = "hints";
  version = "0-unstable-2025-11-15";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "AlfredoSequeida";
    repo = "hints";
    rev = "6dc66ba1481cb568dfa653a32cd1d1ea3970783c";
    hash = "sha256-zaD81dxx2zuDqu9WCkTebhNSO09uPACjd+MZ/SpD+vE=";
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version"
      "branch"
    ];
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
