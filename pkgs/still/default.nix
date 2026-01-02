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
  version = "0.0.8";

  src = fetchFromGitHub {
    owner = "faergeek";
    repo = "still";
    rev = "v${version}";
    hash = "sha256-Ld93xCTgxK4NI4aja6VBYdT9YJHDtoHuiy0c18ACv6M=";
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
