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
  version = "unstable-2026-06-01";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "AlfredoSequeida";
    repo = "hints";
    rev = "e0146c9feff3102b3d944b5c7c09d75a13e1dc51";
    hash = "sha256-ZR8gePSpkM9VrdYV8PClyNzJ1DMDes9yaJcjDjgRENs=";
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

  meta = {
    description = "Keyboard-driven GUI navigation via on-screen hints";
    homepage = "https://github.com/AlfredoSequeida/hints";
    license = lib.licenses.gpl3Only;
    maintainers = [ lib.maintainers.pschmitt ];
    mainProgram = "hints";
    platforms = lib.platforms.linux;
  };
}
