{ pkgs, ... }:
{
  home.packages = with pkgs; [
    brightnessctl
    hyprpicker
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
