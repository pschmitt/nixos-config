{ pkgs, ... }:
{
  home.packages = with pkgs; [
    brightnessctl
    hyprpicker
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
