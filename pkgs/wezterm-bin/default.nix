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

  src = fetchurl {
    url = "https://github.com/wez/wezterm/releases/download/nightly/wezterm-nightly.Ubuntu22.04.tar.xz";
    sha256 = "sha256-WP9iMQl0vELaSX92+F5sPiUmlfoy/IqlklIJSXok3bU=";
  };

  terminfo = fetchurl {
    url = "https://raw.githubusercontent.com/wez/wezterm/90ca1117bc68e3644b1763460e17cf4b6ffbf1c3/termwiz/data/wezterm.terminfo";
    sha256 = "sha256-P+mUyBjCvblCtqOmNZlc2bqUU32tMNWpYO9g25KAgNs=";
  };

  nativeBuildInputs = [ pkg-config python3 perl openssl ];

  # prevent further changes to the RPATH
  dontPatchELF = true;

  installPhase = ''
    mkdir -p $out/share/terminfo/w
    cp -a ./usr/* $out/
    cp -a $terminfo $out/share/terminfo/w/wezterm
  '';

  postFixup = ''
    for artifact in wezterm wezterm-gui wezterm-mux-server strip-ansi-escapes; do
     patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$out/bin/$artifact" || true
     patchelf --set-rpath "${rpath}" $out/bin/$artifact
    done
  '';

  meta = with lib; {
    description = "Wezterm terminal (pre-compiled binary version)";
    homepage = "https://github.com/wez/wezterm";
    license = licenses.gpl3Plus;
    maintainers = [ maintainers.pinpox ];
    platforms = platforms.all;
  };
}
