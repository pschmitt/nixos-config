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
    still
    swappy
    wf-recorder
  ];
}
