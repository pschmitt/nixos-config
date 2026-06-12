{ pkgs, ... }:
{
  home.packages = with pkgs; [
    brightnessctl
    hyprpicker
    wev
    wlogout
    wofi
    wofi-menu # run/emoji/soundboard menus (subset of ~/bin/wofi.zsh)

    # screenshots
    grim
    satty
    slurp
    still
    swappy
    wf-recorder
  ];
}
