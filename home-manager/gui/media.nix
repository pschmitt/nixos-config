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

  xdg.configFile = {
    # Ctrl+Alt+d deletes the current file (formerly in yadm)
    "mpv/input.conf".source = ./mpv-input.conf;

    # rygel: expose playerctld (the active MPRIS player) over UPnP/DLNA.
    # The package defaults would also share media folders (MediaExport) and
    # act as a renderer (Playbin), and leave MPRIS off. LocalSearch stays on:
    # without a second plugin rygel gives up ("No plugins found in 5
    # seconds"), as the MPRIS plugin ignores read-only players.
    "rygel.conf".source = (pkgs.formats.ini { }).generate "rygel.conf" {
      MPRIS.enabled = true;
      "org.mpris.MediaPlayer2.playerctld" = {
        enabled = true;
        title = "playerctld on @HOSTNAME@";
      };
      MediaExport.enabled = false;
      Playbin.enabled = false;
    };

    # Enable the rygel systemd user service
    "systemd/user/default.target.wants/rygel.service".source =
      "${pkgs.rygel}/share/systemd/user/rygel.service";
  };
}
