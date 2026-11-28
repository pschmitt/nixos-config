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
    ./0005-place-cursor-before-releasing-capture.patch
    ./0006-release-input-without-serial-waits.patch
    ./0007-cursor-and-animation-settings.patch
    ./0008-hide-released-target-cursor.patch
    ./0009-filter-pre-grab-motion.patch
    ./0010-limit-entry-motion-bursts.patch
    ./0011-ramp-entry-motion.patch
    ./0012-reveal-cursor-at-placement.patch
    ./0013-handoff-animation-styles.patch
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
