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
    # pschmitt/noctalia-plugins' syncthing plugin). This threads an optional 3rd `icon`
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

      # Luau ui.button has no way to tint its own glyph: the variant's palette
      # owns the ink, so a tooltip-carrying status icon (the only kind there
      # is — ui.glyph takes no tooltip) is stuck at on_surface. This adds a
      # `color` prop that overrides the content color while leaving the
      # background, border, and hover animation to the variant, which is what
      # the syncthing plugin's folder/device rows need for their green checks
      # and violet power glyphs. Drop once upstream adds this itself.
      ./patches/noctalia/0004-button-content-color.patch

      # 0003-batch-http-stream-lines.patch (httpStream line-batching, written
      # for the syncthing plugin's events-API attempt) is intentionally not
      # applied: that plugin rewrite was reverted 2026-09-05 (see
      # profiles/laptop/noctalia.nix) after httpStream's own stream-key reuse
      # turned out to race the plugin's reconnect pattern, and nothing else in
      # this repo uses noctalia.httpStream. Left in the patches directory in
      # case a future attempt needs it again.
    ];
  });
}

# vim: set ft=nix et ts=2 sw=2 :
