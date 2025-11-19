{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    brightnessctl
    hyprpicker
    wev
    wlogout
    wofi

    # screenshots
    grim
    (pkgs.writeShellScriptBin "grim-hyprland" ''
      exec -a $0 ${inputs.grim-hyprland.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/grim "$@"
    '')
    slurp
    swappy
    wayfreeze
    wf-recorder
  ];
}
