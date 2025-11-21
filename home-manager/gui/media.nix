{ pkgs, ... }:
let
  mpvPkg = pkgs.mpv.override { scripts = [ pkgs.mpvScripts.mpris ]; };
in
{
  imports = [
    ./obs-studio.nix
    ./jellysync.nix
  ];

  home.packages = with pkgs; [
    # FIXME ustreamer fails to build as of 2025-11-15
    # ustreamer
    master.easyeffects
    ffmpeg-full
    imagemagick
    mpvPkg
    v4l-utils
    vlc
    yt-dlp
  ];

  # Enable the rygel systemd user service
  xdg.configFile."systemd/user/default.target.wants/rygel.service".source =
    "${pkgs.rygel}/share/systemd/user/rygel.service";
}
