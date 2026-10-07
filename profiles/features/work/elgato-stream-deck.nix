{ pkgs, config, ... }:
let
  streamcontrollerPkg = pkgs.master.streamcontroller;
in
{
  environment.systemPackages = [ streamcontrollerPkg ];

  systemd.user.services.streamcontroller = {
    enable = false;
    description = "An elegant Linux app for the Elgato Stream Deck with support for plugins";
    documentation = [ "https://github.com/StreamController/StreamController" ];
    path = [
      "${config.mainUser.homeDirectory}"
      "/run/current-system/sw"
      "/etc/profiles/per-user/${config.mainUser.username}"
    ];
    serviceConfig =
      let
        streamcontrollerBin = "${streamcontrollerPkg}/bin/streamcontroller --data %E/streamcontroller";
      in
      {
        # ExecStartPre = "-${streamcontrollerBin} --close-running";
        ExecStart = "${streamcontrollerBin} -b";
        ExecStop = "${streamcontrollerBin} --close-running";
        Restart = "on-failure";
        RestartSec = "5";
      };
    wantedBy = [ "default.target" ];
  };

}
