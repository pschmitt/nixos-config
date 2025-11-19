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
    slurp
    swappy
    wayfreeze
    wf-recorder
  ];
}
