{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  wayland, # provides wayland-scanner used at build time
  wayland-protocols,
  wayland-scanner,
  pixman,
  scdoc, # to build the man page from still.1.scd
}:

stdenv.mkDerivation rec {
  pname = "still";
  version = "0.0.7";

  src = fetchFromGitHub {
    owner = "faergeek";
    repo = "still";
    rev = "v${version}";
    hash = "sha256-tPDPEUBVfNNnTULRNuqyshfvjb1otiko3KlsAj46qRY=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wayland
    wayland-protocols
    wayland-scanner
    scdoc
  ];

  buildInputs = [
    pixman
  ];

  # meson hooks handle configure/build/install; no custom phases needed

  meta = with lib; {
    description = "Freeze the screen of a Wayland compositor until a provided command exits";
    homepage = "https://github.com/faergeek/still";
    changelog = "https://github.com/faergeek/still/blob/${src.rev}/CHANGELOG.md";
    license = licenses.mit;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "still";
    platforms = platforms.linux;
  };
}
