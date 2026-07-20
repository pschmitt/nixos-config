{
  inputs,
  final,
  prev,
}:
let
  inherit (final.stdenv.hostPlatform) system;
  base = inputs.hyprland.packages.${system}.xdg-desktop-portal-hyprland;
  patches-src = inputs.cpuguy83-nixcfg;
in
{
  xdg-desktop-portal-hyprland = base.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      "${patches-src}/patches/xdph/0001-feature-ui-improvements.patch"
      "${patches-src}/patches/xdph/0002-add-icons.patch"
      "${patches-src}/patches/xdph/0003-remove-share-token-ui.patch"
      # 0004 upstream (cpuguy83-nixcfg) no longer applies cleanly: xdph now
      # ships its own `dependency('hyprutils')` in meson.build, so the
      # meson.build hunk conflicts. Carry a locally-adjusted copy instead.
      ./patches/xdph/0004-show-virtual-desktop.patch
      "${patches-src}/patches/xdph/0005-live-window-preview.patch"
      "${patches-src}/patches/xdph/0006-screen-preview.patch"
    ];
    postPatch = (old.postPatch or "") + ''
      substituteInPlace hyprland-share-picker/CMakeLists.txt \
        --replace-fail "/usr/share/wayland/wayland.xml" \
        "${final.wayland-scanner}/share/wayland/wayland.xml"

      # 0003 hides the restore-token checkbox behind an env var; always show it
      substituteInPlace hyprland-share-picker/main.cpp \
        --replace-fail \
          'getenv("XDPH_PICKER_ALLOW_TOKEN_SELECTION") != nullptr' \
          'true'

      # 0005 defaults live-preview to 500 ms (2 fps); use 100 ms (10 fps) instead
      substituteInPlace hyprland-share-picker/waylandcapture.h \
        --replace-fail 'int intervalMs = 500' 'int intervalMs = 100' \
        --replace-fail 'int m_liveIntervalMs = 500' 'int m_liveIntervalMs = 100'
    '';
  });
}

# vim: set ft=nix et ts=2 sw=2 :
