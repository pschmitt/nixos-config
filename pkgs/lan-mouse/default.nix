{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, wrapGAppsHook4
, cairo
, gdk-pixbuf
, glib
, gtk4
, libadwaita
, pango
, stdenv
, darwin
, wayland
, xorg
}:

rustPlatform.buildRustPackage rec {
  pname = "lan-mouse";
  version = "latest";

  src = fetchFromGitHub {
    owner = "feschber";
    repo = "lan-mouse";
    rev = version;
    hash = "sha256-FCU7Lcc51doQL2v1H0kpwRcJgO+oeWhrqrFHUcV5N1Y=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "reis-0.1.0" = "sha256-ZSoxtZLV8ricsZKNgFBEQ39D9hfl28jniXRmn7Ik3bo=";
    };
  };

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    cairo
    gdk-pixbuf
    glib
    gtk4
    libadwaita
    pango
  ] ++ lib.optionals stdenv.isDarwin [
    darwin.apple_sdk.frameworks.CoreGraphics
  ] ++ lib.optionals stdenv.isLinux [
    wayland
    xorg.libX11
    xorg.libXtst
  ];

  meta = with lib; {
    description = "Mouse & keyboard sharing via LAN";
    homepage = "https://github.com/feschber/lan-mouse";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ pschmitt ];
    mainProgram = "lan-mouse";
  };
}
