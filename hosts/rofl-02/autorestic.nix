{ lib, pkgs, ... }:

let
  createService = name: scriptPath: {
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.docker
      pkgs.nettools
      pkgs.util-linux # for umount
    ];
    script = "${scriptPath}";
  };

  createTimer = name: time: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = time;
      RandomizedDelaySec = "600";
      Persistent = true;
    };
  };

  # Service and timer configurations
  services = {
    "autorestic-remote-turris" = {
      path = "/srv/autorestic-remote/autorestic-remote.sh turris";
      time = "03:00";
    };
    "autorestic-remote-wrt1900ac" = {
      path = "/srv/autorestic-remote/autorestic-remote.sh wrt1900ac";
      time = "04:00";
    };
  };
in
{
  systemd.services = lib.mapAttrs' (
    name: cfg: lib.nameValuePair name (createService name cfg.path)
  ) services;
  systemd.timers = lib.mapAttrs' (
    name: cfg: lib.nameValuePair (name) (createTimer name cfg.time)
  ) services;
}
