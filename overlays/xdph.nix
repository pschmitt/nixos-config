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
      "${patches-src}/patches/xdph/0004-show-virtual-desktop.patch"
      "${patches-src}/patches/xdph/0005-live-window-preview.patch"
      "${patches-src}/patches/xdph/0006-screen-preview.patch"
    ];
    postPatch = (old.postPatch or "") + ''
      substituteInPlace hyprland-share-picker/CMakeLists.txt \
        --replace-fail "/usr/share/wayland/wayland.xml" \
        "${final.wayland-scanner}/share/wayland/wayland.xml"
    '';
  });
}

# vim: set ft=nix et ts=2 sw=2 :
