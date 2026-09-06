{
  lib,
  stdenvNoCC,
  wrapGAppsHook4,
  python3,
  cairo,
  gdk-pixbuf,
  graphene,
  glib,
  gobject-introspection-unwrapped,
  grim,
  gtk4,
  gtk4-layer-shell,
  hyprland,
  pango,
  slurp,
}:

let
  pythonWithGtk = python3.withPackages (pythonPackages: [
    pythonPackages.pycairo
    pythonPackages.pygobject3
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "hyprland-share-picker-gtk";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./hyprland_share_picker.py
      ./hyprland-share-picker-gtk
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    wrapGAppsHook4
  ];

  buildInputs = [
    cairo
    gdk-pixbuf
    graphene
    glib
    gobject-introspection-unwrapped
    gtk4
    gtk4-layer-shell
    pango
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 hyprland_share_picker.py \
      "$out/share/hyprland-share-picker-gtk/hyprland_share_picker.py"
    install -Dm755 hyprland-share-picker-gtk \
      "$out/bin/hyprland-share-picker-gtk"

    substituteInPlace "$out/bin/hyprland-share-picker-gtk" \
      --replace-fail '@python@' '${pythonWithGtk}/bin/python' \
      --replace-fail '@script@' "$out/share/hyprland-share-picker-gtk/hyprland_share_picker.py"

    runHook postInstall
  '';

  meta = {
    description = "GTK4 screencast source picker for xdg-desktop-portal-hyprland";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
