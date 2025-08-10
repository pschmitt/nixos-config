{ pkgs, ... }:
let
  mpvPkg = pkgs.mpv.override { scripts = [ pkgs.mpvScripts.mpris ]; };
in
{
  imports = [ ./obs-studio.nix ];

  home.packages = with pkgs; [
    # Media
    ffmpeg-full
    mpvPkg
    ustreamer
    v4l-utils
    vlc
  ];

  # Enable the rygel systemd user service
  xdg.configFile."systemd/user/default.target.wants/rygel.service".source =
    "${pkgs.rygel}/share/systemd/user/rygel.service";
}
