{
  fetchFromGitHub,
  autoPatchelfHook,
  lib,
  onnxruntime,
  pkg-config,
  pipewire,
  rustPlatform,
  wayland,
  libxkbcommon,
  openssl,
  zlib,
}:

let
  source = fetchFromGitHub {
    owner = "Netflate";
    repo = "LumineCapture";
    rev = "v0.2.0";
    hash = "sha256-AdPGPoyqpWAQhhxTg2j6AR7N3rscAU1fHwMhvEr5ti8=";
  };
in
rustPlatform.buildRustPackage {
  pname = "lumine-capture";
  version = "0.2.0";

  src = source;

  cargoLock.lockFile = "${source}/Cargo.lock";

  nativeBuildInputs = [
    autoPatchelfHook
    pkg-config
    rustPlatform.bindgenHook
  ];

  ORT_LIB_LOCATION = "${onnxruntime}/lib";
  ORT_PREFER_DYNAMIC_LINK = "1";

  buildInputs = [
    libxkbcommon
    openssl
    onnxruntime
    pipewire
    wayland
    zlib
  ];

  postInstall = ''
    install -Dm644 assets/lumine-capture.desktop $out/share/applications/lumine-capture.desktop
    for icon in assets/hicolor/*/apps/*; do
      install -Dm644 "$icon" "$out/share/icons/hicolor/''${icon#assets/hicolor/}"
    done
  '';

  meta = {
    description = "Screenshot and annotation tool for Wayland with built-in OCR";
    homepage = "https://github.com/Netflate/LumineCapture";
    license = [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    mainProgram = "lumine-capture";
    platforms = lib.platforms.linux;
  };
}
