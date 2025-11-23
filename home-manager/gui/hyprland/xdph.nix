# { inputs, pkgs, ... }:
{
  # wayland.windowManager.hyprland.portalPackage =
  #   let
  #     xdphPatched =
  #       inputs.xdph.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland.overrideAttrs
  #         (old: {
  #           # Point hyprland-share-picker to the packaged wayland.xml instead of /usr.
  #           postPatch = (old.postPatch or "") + ''
  #             substituteInPlace hyprland-share-picker/CMakeLists.txt \
  #               --replace-fail "/usr/share/wayland/wayland.xml" \
  #               "${pkgs.wayland}/share/wayland/wayland.xml"
  #           '';
  #         });
  #   in
  #   xdphPatched;

  # Mirror ~/.config/hypr/xdph.conf for xdg-desktop-portal-hyprland.
  xdg.configFile."hypr/xdph.conf".text = ''
    screencopy {
      allow_token_by_default = true
    }
  '';
}
