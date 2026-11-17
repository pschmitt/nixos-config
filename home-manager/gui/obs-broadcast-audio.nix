{ pkgs, ... }:
let
  controller = pkgs.writeShellApplication {
    name = "obs-broadcast-audio";
    runtimeInputs = [
      pkgs.pipewire
      pkgs.pulseaudio
      pkgs.systemd
    ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${./obs-broadcast-audio.py} "$@"
    '';
  };
in
{
  home.packages = [ controller ];

  home.file.".config/obs-studio/scripts/obs-broadcast-audio.lua".source = ./obs-broadcast-audio.lua;

  systemd.user.services.obs-broadcast-audio = {
    Unit = {
      Description = "Opt-in OBS broadcast audio into Meeting Microphone";
      PartOf = [ "graphical-session.target" ];
      After = [
        "pipewire.service"
        "pipewire-pulse.service"
        "wireplumber.service"
      ];
      Requisite = [
        "pipewire.service"
        "pipewire-pulse.service"
        "wireplumber.service"
      ];
    };
    Service = {
      ExecStart = "${controller}/bin/obs-broadcast-audio run";
      ExecStopPost = "${controller}/bin/obs-broadcast-audio cleanup";
      Restart = "no";
      TimeoutStopSec = 5;
      UMask = "0077";
      RuntimeDirectory = "obs-broadcast-audio";
      RuntimeDirectoryMode = "0700";
    };
  };
}
