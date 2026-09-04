{
  inputs,
  final,
  ...
}:
let
  inherit (final.stdenv.hostPlatform) system;
  base = inputs.noctalia.packages.${system}.default;
in
{
  noctalia = base.overrideAttrs (old: {
    # Upstream's Luau plugin API (noctalia.notify/notifyError) hardcodes the
    # notification appName to "Noctalia" and never forwards an icon, so every
    # plugin's notifications show the generic Noctalia icon (e.g.
    # pkgs/local/noctalia-syncthing). This threads an optional 3rd `icon`
    # argument through luau_notify/luau_notifyError -> LuauHost::scriptNotify*
    # -> the NotifyInfo/NotifyError side effect (reusing its existing `extra`
    # field) -> notify::info/error -> NotificationManager::addInternal, which
    # already accepted an icon but had no caller wiring one up. Plugins can
    # pass an absolute path (e.g. `noctalia.pluginDir() .. "/assets/foo.svg"`)
    # as the 3rd arg. Drop once upstream adds this itself.
    patches = (old.patches or [ ]) ++ [
      ./patches/noctalia/0001-plugin-notify-icon.patch

      # Luau ui.image controls were rasterized at 3x their display size with
      # mipmapping enabled, making small SVG plugin icons permanently soft.
      # Rasterize them at the exact device-pixel size without mipmaps instead;
      # other image consumers retain their own downscaling behavior. Drop once
      # upstream fixes this itself.
      ./patches/noctalia/0002-sharp-ui-image.patch
    ];
  });
}

# vim: set ft=nix et ts=2 sw=2 :
