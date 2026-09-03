{
  lib,
  stdenvNoCC,
  imagemagick,
  roboto,
  power-profiles-daemon,
  sound-theme-freedesktop,
  systemd,
}:

stdenvNoCC.mkDerivation {
  pname = "noctalia-battery-icon";
  version = "0.2.5";

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
    cp -L ${sound-theme-freedesktop}/share/sounds/freedesktop/stereo/power-unplug.oga "$dest"/sounds/unplug.oga
    substitute service.luau "$dest"/service.luau \
      --subst-var-by magick ${imagemagick}/bin/magick \
      --subst-var-by font ${roboto}/share/fonts/truetype/Roboto-Bold.ttf \
      --subst-var-by powerprofilesctl ${power-profiles-daemon}/bin/powerprofilesctl \
      --subst-var-by udevadm ${systemd}/bin/udevadm

    runHook postInstall
  '';

  meta = {
    description = "Material 3 Expressive battery indicator widget for Noctalia";
    license = lib.licenses.gpl3Only;
    maintainers = [ lib.maintainers.pschmitt ];
    platforms = lib.platforms.linux;
  };
}
