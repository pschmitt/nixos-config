{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  pixman,
  scdoc,
  wayland,
  wayland-protocols,
  wayland-scanner,
}:

stdenv.mkDerivation rec {
  pname = "still";
  version = "0.0.10";

  src = fetchFromGitHub {
    owner = "faergeek";
    repo = "still";
    rev = "v${version}";
    hash = "sha256-4ysI2U4k93ccC8gRoA+AcgTamSIL1ficLfqS8bc8vlY=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    scdoc
    wayland-scanner
  ];

  buildInputs = [
    pixman
    wayland
    wayland-protocols
  ];

  meta = {
    description = "Freeze the screen of a Wayland compositor until a provided command exits";
    homepage = "https://github.com/faergeek/still";
    changelog = "https://github.com/faergeek/still/blob/${src.rev}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    mainProgram = "still";
    platforms = lib.platforms.all;
  };
}
