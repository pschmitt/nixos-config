{
  lib,
  stdenv,
  fetchFromGitHub,
  cairo,
  libxkbcommon,
  meson,
  ninja,
  pkg-config,
  wayland,
  wayland-protocols,
}:

stdenv.mkDerivation rec {
  pname = "wl-kbptr";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "moverest";
    repo = "wl-kbptr";
    rev = "v${version}";
    hash = "sha256-8fkW8TCP7tNTvCHUe8VTZMGyLTnWjiC/So+n2wiNW9M=";
  };

  nativeBuildInputs = [
    cairo
    libxkbcommon
    meson
    ninja
    pkg-config
    wayland
    wayland-protocols
  ];

  meta = with lib; {
    description = "Control the mouse pointer with the keyboard on Wayland";
    homepage = "https://github.com/moverest/wl-kbptr";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "wl-kbptr";
    platforms = platforms.all;
  };
}
