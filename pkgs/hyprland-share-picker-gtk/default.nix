{
  lib,
  rustPlatform,
  pkg-config,
  glib,
  gtk4,
  gtk4-layer-shell,
  wayland,
  cairo,
  pango,
  gdk-pixbuf,
  libglvnd,
  libgbm,
  slurp,
  makeWrapper,
}:

rustPlatform.buildRustPackage {
  pname = "hyprland-share-picker-gtk";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.lock
      ./Cargo.toml
      ./src
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [
    pkg-config
    glib
    makeWrapper
  ];

  buildInputs = [
    gtk4
    gtk4-layer-shell
    wayland
    glib
    cairo
    pango
    gdk-pixbuf
    libglvnd
    libgbm
  ];

  postInstall = ''
    wrapProgram $out/bin/hyprland-share-picker-gtk \
      --prefix PATH : ${lib.makeBinPath [ slurp ]}
  '';

  meta = {
    description = "A smooth GTK4 share picker for Hyprland and xdg-desktop-portal-hyprland";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hyprland-share-picker-gtk";
  };
}
