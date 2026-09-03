{ ... }:
{
  imports = [
    ./clipboard.nix
    ./monitors.nix
    ./hyprevents.nix
    ./hypridle.nix
    ./hyprlock.nix
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
    ./xdg-portal-screencast-watcher.nix
  ];
}
