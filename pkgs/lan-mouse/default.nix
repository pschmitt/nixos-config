{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook4,
  cairo,
  gdk-pixbuf,
  glib,
  gtk4,
  libadwaita,
  pango,
  stdenv,
  darwin,
  wayland,
  xorg,
}:

rustPlatform.buildRustPackage {
  pname = "lan-mouse";
  version = "latest-cdd3a3";

  src = fetchFromGitHub {
    owner = "feschber";
    repo = "lan-mouse";
    rev = "cdd3a3b818e2a9401699ba4d2e8d453041b29494";
    hash = "sha256-J5b3pjoDP2hMvD5TIJT6A2Ox3XtdZ13AQd4ltJ0/gQI=";
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "reis-0.1.0" = "sha256-iV5nX3LI58jZE+2Z0YYOAELO++Ta+GUkRQZMZ94Np0E=";
    };
  };

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs =
    [
      cairo
      gdk-pixbuf
      glib
      gtk4
      libadwaita
      pango
    ]
    ++ lib.optionals stdenv.isDarwin [ darwin.apple_sdk.frameworks.CoreGraphics ]
    ++ lib.optionals stdenv.isLinux [
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
