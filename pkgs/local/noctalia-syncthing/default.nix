{
  lib,
  stdenvNoCC,
  librsvg,
}:

stdenvNoCC.mkDerivation {
  pname = "noctalia-syncthing";
  version = "2.1.1";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./plugin.toml
      ./bar.luau
      ./service.luau
      ./panel.luau
      ./desktop.luau
      ./launcher.luau
      ./shortcut.luau
      ./lib
      ./assets
      ./translations
    ];
  };

  nativeBuildInputs = [ librsvg ];

  dontConfigure = true;
  dontBuild = true;

  # Noctalia's ui.image SVG loader drops <linearGradient>/<mask> defs (the
  # badge SVGs render as a bare monochrome outline instead of the blue
  # syncthing logo + colored badge), so rasterize them to PNG at build time
  # instead. Use rsvg-convert directly, not `magick`: ImageMagick's own
  # SVG-to-PNG path ignores `-background none` here and flattens the
  # transparent areas to opaque white, no matter how the depth/alpha flags
  # are juggled — rsvg-convert (the delegate ImageMagick itself would shell
  # out to) renders the exact same file with correct alpha in one step.
  installPhase = ''
    runHook preInstall

    dest=$out/share/noctalia-plugins/syncthing
    mkdir -p "$dest"/assets

    cp plugin.toml bar.luau service.luau panel.luau desktop.luau launcher.luau shortcut.luau "$dest"/
    cp -r lib translations "$dest"/
    for svg in assets/status-*.svg; do
      rsvg-convert -w 256 -h 256 -o "$dest/assets/$(basename "''${svg%.svg}.png")" "$svg"
    done

    runHook postInstall
  '';

  meta = {
    description = "Fork of rylos/syncthing with a tray-sized bar icon and DMS-style composited status badges";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
  };
}
