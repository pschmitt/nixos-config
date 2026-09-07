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

      # The Hyprland keyboard-layout widget could only ever show de/us here,
      # never the HHKB's own hhkb-de (per-device kb_layout, see
      # home-manager/gui/hyprland/conf/input.nix). Two upstream bugs stack up:
      # hyprland_keyboard_backend.cpp defines seedLayoutFromDevices() but
      # never calls it, so m_mainKeyboardName stays empty and handleEvent()'s
      # "only the main keyboard" filter is inert -- and since Hyprland emits
      # one `activelayout` event per keyboard on every switch, the last event
      # of the burst wins. Seeding alone isn't enough either: Hyprland points
      # `main` at whichever device last produced input, which is regularly
      # noctalia's own hl-virtual-keyboard-.noctalia-wrapped, and that one
      # only carries the global input:kb_layout. So also skip virtual
      # keyboards when picking, and re-resolve (throttled) when events stop
      # matching the current pick. Also recover the layout name lazily from
      # the const accessors: the constructor's seed loses the race with IPC
      # readiness often enough that the widget would otherwise stay hidden
      # as a "single layout" until the next switch -- and report the real
      # layout list from `j/devices` rather than a one-element one, since the
      # widget's hide-when-single-layout check otherwise only ever sees the
      # wl_seat's list, which is empty whenever noctalia holds no keyboard
      # focus. Drop once upstream handles this itself.
      ./patches/noctalia/0005-hyprland-main-keyboard-layout.patch

      # On every noctalia start the keyboard-layout OSD popped up announcing
      # a layout nobody switched to ("DE", while the HHKB was on hhkb-de).
      # KeyboardLayoutOsd::prime() records the current layout so the first
      # change isn't announced, but it marks itself primed even when that
      # name is still empty -- so the first real name to arrive reads as a
      # change. Stay unprimed until there is something to compare against.
      # Drop once upstream handles this itself.
      ./patches/noctalia/0006-keyboard-layout-osd-prime.patch

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
