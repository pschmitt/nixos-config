{
  lib,
  pkgs,
  ...
}:
let
  ppdReact = pkgs.writeShellApplication {
    name = "ppd-react";
    runtimeInputs = with pkgs; [
      gawk
      jq
      libnotify
      systemd
      util-linux
    ];
    text = builtins.readFile ./ppd-react.sh;
  };
in
{
  # power-profiles-daemon conflicts with tlp
  # https://linrunner.de/tlp/faq/ppd.html
  services = {
    power-profiles-daemon.enable = lib.mkForce true;
    tlp.enable = lib.mkForce false;
  };

  systemd.services.ppd-react = {
    description = "React to power-profiles-daemon profile changes";
    wantedBy = [ "multi-user.target" ];
    after = [
      "dbus.service"
      "power-profiles-daemon.service"
    ];
    wants = [ "power-profiles-daemon.service" ];
    environment.NOTIFY = "1";

    serviceConfig = {
      ExecStart = "${ppdReact}/bin/ppd-react";
      Restart = "always";
      RestartSec = "1s";
    };
  };
}
