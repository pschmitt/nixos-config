{ pkgs, ... }:
{
  home.packages = with pkgs; [
    brightnessctl
    hyprpicker
    libnotify # notify-send — fallback for osd(1) and other scripts when dms isn't active; no longer pulled in via mako.nix
    osd # ad-hoc OSD/toast CLI (DMS toast IPC, falls back to notify-send/mako)
    wev
    walker-menu # soundboard/misc/meetings dmenu menus
    wlogout

    # screenshots
    grim
    satty
    slurp
    still
    swappy
    wf-recorder
  ];
}
