{
  lib,
  rustPlatform,
  fetchurl,
  pkg-config,
  makeWrapper,
  libpulseaudio,
  udev,
  libglvnd,
  wayland,
  libxkbcommon,
  libx11,
  libxcursor,
  libxi,
  libxrandr,
}:
let
  uiLibraries = [
    libglvnd
    wayland
    libxkbcommon
    libx11
    libxcursor
    libxi
    libxrandr
  ];
in
rustPlatform.buildRustPackage {
  pname = "mickey";
  version = "0.6.0";

  src = fetchurl {
    url = "https://codeload.github.com/EduardoMG12/mickey/tar.gz/84aabf2f53157542c8b5da579318e0984e4e1161";
    name = "mickey-0.6.0.tar.gz";
    hash = "sha256-mwcKf/rsECmk7mHtxfVJ7KokEYABaAgfAZ9leZwHHWc=";
  };
  cargoLock.lockFile = ./Cargo.lock;

  patches = [
    ./0001-resolve-peer-hostnames.patch
    ./0002-linux-input-hotplug.patch
    ./0003-wake-on-edge-crossing.patch
    ./0004-handoff-feedback.patch
  ];

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];
  buildInputs = [
    libpulseaudio
    udev
    wayland
  ];

  cargoBuildFlags = [ "--workspace" ];
  cargoTestFlags = [ "--workspace" ];

  postInstall = ''
    install -Dm644 packaging/linux/mickey-settings.desktop "$out/share/applications/mickey-settings.desktop"
    install -Dm644 packaging/linux/mickey.png "$out/share/icons/hicolor/256x256/apps/mickey.png"
    install -Dm644 LICENSE "$out/share/licenses/mickey/LICENSE"
    wrapProgram "$out/bin/mickey-ui" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath uiLibraries}:/run/opengl-driver/lib"
  '';

  meta = {
    description = "Share a keyboard and mouse across computers";
    homepage = "https://github.com/EduardoMG12/mickey";
    license = lib.licenses.gpl3Plus;
    mainProgram = "mickey";
    platforms = [ "x86_64-linux" ];
  };
}
