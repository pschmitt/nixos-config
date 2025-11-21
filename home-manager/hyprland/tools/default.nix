{ pkgs, ... }:
{
  home.packages = with pkgs; [
    brightnessctl
    hyprpicker
    wev
    wlogout
    wofi

    # screenshots
    grim
    satty
    slurp
    swappy
    wayfreeze
    wf-recorder
  ];
}
