{ pkgs, ... }:
{
  home.packages = with pkgs; [
    brightnessctl
    hyprpicker
    libnotify # notify-send fallback for osd(1) and other scripts
    osd # ad-hoc OSD/toast CLI
    screencast-state # live xdg-desktop-portal screencasts, read from PipeWire
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
