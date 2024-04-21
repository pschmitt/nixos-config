{ lib, pkgs, ... }:

let
  createService = name: scriptPath: {
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${scriptPath}";
      Environment = "PATH=${lib.makeBinPath [ pkgs.bash pkgs.coreutils pkgs.docker ]}";
    };
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
    "autorestic-backup" = {
      path = "/mnt/data/bin/autorestic backup --all --verbose --ci";
      time = "06:00";
    };
    "autorestic-remote-oci-02" = {
      path = "/srv/autorestic-remote/autorestic-remote.sh oci-02";
      time = "15:00";
    };
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
  systemd.services = lib.mapAttrs' (name: cfg: lib.nameValuePair name (createService name cfg.path)) services;
  systemd.timers = lib.mapAttrs' (name: cfg: lib.nameValuePair (name) (createTimer name cfg.time)) services;
}

