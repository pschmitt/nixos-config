{ ... }:
{
  imports = [
    ./clipboard.nix
    ./monitors.nix
    ./hyprevents.nix
    ./hypridle.nix
    # hyprlock.nix is intentionally not imported: Noctalia now manages the
    # session lock natively (profiles/laptop/noctalia.nix, lockscreen.enabled)
    # on every host that imports this module. File kept for reference / a
    # one-line revert if a host ever drops Noctalia.
    # ./hyprlock.nix
    ./iio-hyprland.nix
    # hyprpaper.nix is intentionally not imported: Noctalia now manages the
    # wallpaper natively (profiles/laptop/noctalia.nix, wallpaper.default.path)
    # on every host that imports this module, so a separate wallpaper daemon
    # would just fight it for the same output. File kept for reference / a
    # one-line revert if a host ever drops Noctalia.
    # ./hyprpaper.nix
    # mako.nix is intentionally not imported: DMS is now the sole
    # bar/notification daemon on every host that imports this module (all
    # three currently also enable programs.dank-material-shell — see
    # profiles/laptop/dank-material-shell.nix), and DMS implements its own
    # org.freedesktop.Notifications server, so notify-send-based scripts
    # keep working without mako running. The file is kept (not deleted) so
    # re-enabling this is a one-line revert if a host ever falls back to
    # waybar via toggle-bar.sh.
    # ./mako.nix
    ./polkit.nix
    # Disabled: this busctl watcher only existed to fire
    # screencast.sh on|off, whose notify-send now duplicates Noctalia's
    # native privacy OSD (osd.privacy.screen-on/off). The Home Assistant
    # screencast sensor no longer needs its /tmp/screencast.json either —
    # go-hass-agent/scripts/screencast.sh reads the PipeWire graph directly,
    # like the pschmitt/screencast Noctalia plugin does. Kept (not deleted)
    # so re-enabling is a one-line revert, same as mako.nix above.
    # ./xdg-portal-screencast-watcher.nix
  ];
}
