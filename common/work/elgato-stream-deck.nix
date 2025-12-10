{ pkgs, config, ... }:
let
  streamcontrollerPkg = pkgs.streamcontroller.streamcontroller;
in
{
  environment.systemPackages = with pkgs; [
    deckmaster
    streamcontrollerPkg
  ];

  systemd.user.services.deckmaster = {
    enable = false;
    description = "An application to control your Elgato Stream Deck on Linux";
    documentation = [ "https://github.com/muesli/deckmaster" ];
    path = [
      "${config.mainUser.homeDirectory}"
      "/run/current-system/sw"
      "/etc/profiles/per-user/${config.mainUser.username}"
    ];
    serviceConfig = {
      ExecStart = "${pkgs.deckmaster}/bin/deckmaster --verbose --deck %E/deckmaster/main.deck --brightness 33";
      Restart = "on-failure";
      RestartSec = "3";
    };
    wantedBy = [ "default.target" ];
  };

  systemd.user.services.streamcontroller = {
    enable = true;
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
