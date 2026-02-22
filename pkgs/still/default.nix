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
  version = "0.0.9";

  src = fetchFromGitHub {
    owner = "faergeek";
    repo = "still";
    rev = "v${version}";
    hash = "sha256-bZo4SvBB5pSdvwxuE3+A2iz1um1kSZQ62chR0lOjpj8=";
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
