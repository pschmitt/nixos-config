{
  lib,
  stdenvNoCC,
  imagemagick,
  ComicCodeNF,
  sound-theme-freedesktop,
}:

stdenvNoCC.mkDerivation {
  pname = "noctalia-battery-icon";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./plugin.toml
      ./service.luau
      ./bar.luau
      ./translations
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/share/noctalia-plugins/battery-icon
    mkdir -p "$dest"

    cp plugin.toml bar.luau "$dest"/
    cp -r translations "$dest"/
    mkdir -p "$dest"/sounds
    cp -L ${sound-theme-freedesktop}/share/sounds/freedesktop/stereo/power-plug.oga "$dest"/sounds/charging.oga
    substitute service.luau "$dest"/service.luau \
      --subst-var-by magick ${imagemagick}/bin/magick \
      --subst-var-by font ${ComicCodeNF}/share/fonts/opentype/ComicCodeNerdFont-SemiBold-resized.otf

    runHook postInstall
  '';

  meta = {
    description = "Battery-percentage-inside-icon widget for Noctalia (Android status-bar style)";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ pschmitt ];
    platforms = lib.platforms.linux;
  };
}
