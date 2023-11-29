{ fetchurl
, pkgs
, dbus
, egl-wayland
, fetchFromGitHub
, fontconfig
, freetype
, lib
, libGL
, libGLU
, libX11
, libglvnd # libEGL.so.1
, libiconv
, libxcb
, libxkbcommon
, ncurses
, openssl
, perl
, pkg-config
, python3
, rustPlatform
, stdenv
, wayland
, xcbutil
, xcbutilimage
, xcbutilkeysyms
, xcbutilwm # contains xcb-ewmh among others
, zlib
}:

let
  rpath = lib.makeLibraryPath [
    dbus
    egl-wayland
    fontconfig
    fontconfig.lib
    freetype
    libGL
    libGLU
    libglvnd
    libxkbcommon
    openssl
    wayland
    libX11
    libxcb
    xcbutil
    xcbutilimage
    xcbutilkeysyms
    xcbutilwm
    zlib

  ];

in
stdenv.mkDerivation rec {
  pname = "wezterm-bin";
  version = "nightly-20231129";

  outputs = [ "out" "terminfo" ];

  src = fetchurl {
    url = "https://github.com/wez/wezterm/releases/download/nightly/wezterm-nightly.Ubuntu22.04.tar.xz";
    sha256 = "sha256-WP9iMQl0vELaSX92+F5sPiUmlfoy/IqlklIJSXok3bU=";
  };

  terminfoSrc = fetchurl {
    url = "https://raw.githubusercontent.com/wez/wezterm/90ca1117bc68e3644b1763460e17cf4b6ffbf1c3/termwiz/data/wezterm.terminfo";
    sha256 = "sha256-P+mUyBjCvblCtqOmNZlc2bqUU32tMNWpYO9g25KAgNs=";
  };

  nativeBuildInputs = [ pkg-config python3 perl openssl ncurses ];

  # prevent further changes to the RPATH
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -a ./usr/* $out/

    mkdir -p $terminfo/share/terminfo/w
    tic -xe wezterm -o "$terminfo/share/terminfo" "$terminfoSrc"

    mkdir -p "$out/nix-support"
    echo "$terminfo" >> "$out/nix-support/propagated-user-env-packages"

    runHook postInstall
  '';

  postFixup = ''
    for bin in wezterm wezterm-gui wezterm-mux-server strip-ansi-escapes; do
      patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$out/bin/$bin" || true
      patchelf --set-rpath "${rpath}" "$out/bin/$bin"
    done
  '';

  meta = with lib; {
    description = "Wezterm terminal (pre-compiled binary version)";
    homepage = "https://github.com/wez/wezterm";
    license = licenses.gpl3Plus;
    maintainers = [ maintainers.pschmitt ];
    platforms = platforms.all;
  };
}
