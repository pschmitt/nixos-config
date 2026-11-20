{ pkgs, ... }:
let
  mpvPkg = pkgs.mpv.override { scripts = [ pkgs.mpvScripts.mpris ]; };
in
{
  imports = [
    ./obs-studio.nix
  ];

  home.packages = with pkgs; [
    master.easyeffects
    ffmpeg-full
    gimp
    imagemagick
    mpvPkg
    v4l-utils
    vlc
    yt-dlp
  ];

  # Ctrl+Alt+d deletes the current file (formerly in yadm)
  xdg.configFile."mpv/input.conf".source = ./mpv-input.conf;

  # Enable the rygel systemd user service
  xdg.configFile."systemd/user/default.target.wants/rygel.service".source =
    "${pkgs.rygel}/share/systemd/user/rygel.service";
}
