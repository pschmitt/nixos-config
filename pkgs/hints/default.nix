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
  version = "unstable-2026-01-25";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "AlfredoSequeida";
    repo = "hints";
    rev = "6c15356bbf18d20eaccf501a30144fb3d1b18741";
    hash = "sha256-NnSxVTzVl1/ZWPkuCqZoZc/u+c+nBUpz7ZwtavqT/rg=";
  };

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--flake"
      "--version"
      "branch"
      "--version-regex"
      "(?:0-)?(unstable-[0-9]{4}-[0-9]{2}-[0-9]{2})"
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
