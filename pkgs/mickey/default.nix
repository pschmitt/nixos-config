{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  libpulseaudio,
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
stdenv.mkDerivation (finalAttrs: {
  pname = "mickey";
  version = "0.6.0";

  src = fetchurl {
    url = "https://github.com/EduardoMG12/mickey/releases/download/v${finalAttrs.version}/mickey-linux-x86_64.tar.gz";
    hash = "sha256-vhWH3+Fnx91fZzv0UoE5x+e8z7IfA1zXFqfrBsL3YKk=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    libpulseaudio
    stdenv.cc.cc.lib
  ];

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 mickey "$out/bin/mickey"
    install -Dm755 mickey-ui "$out/bin/mickey-ui"
    install -Dm644 mickey-settings.desktop "$out/share/applications/mickey-settings.desktop"
    install -Dm644 mickey.png "$out/share/icons/hicolor/256x256/apps/mickey.png"
    install -Dm644 LICENSE "$out/share/licenses/mickey/LICENSE"
    install -Dm644 THIRD-PARTY-LICENSES.txt "$out/share/licenses/mickey/THIRD-PARTY-LICENSES.txt"
    wrapProgram "$out/bin/mickey-ui" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath uiLibraries}:/run/opengl-driver/lib"
    runHook postInstall
  '';

  meta = {
    description = "Share a keyboard and mouse across computers";
    homepage = "https://github.com/EduardoMG12/mickey";
    license = lib.licenses.gpl3Only;
    mainProgram = "mickey";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
