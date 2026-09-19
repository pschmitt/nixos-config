{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/srv/watchyourlan/data/wyl";
in
{
  options.services.watchyourlan.interfaces = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ "hass-br0" ];
    description = "Interfaces WatchYourLAN should scan for network discovery.";
  };

  config = {
    systemd.services.watchyourlan = {
      description = "WatchYourLAN network discovery";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ dataDir ];
      environment = {
        HOST = "0.0.0.0";
        PORT = "8840";
        TIMEOUT = "120";
        IFACES = lib.concatStringsSep " " config.services.watchyourlan.interfaces;
        THEME = "sand";
        COLOR = "dark";
        TZ = config.time.timeZone;
      };
      serviceConfig = {
        ExecStart = "${pkgs.watchyourlan}/bin/WatchYourLAN -d ${dataDir}";
        Restart = "on-failure";
        RestartSec = "5s";
        # Preserve the root-owned database and host-network ARP scanning.
        User = "root";
        Group = "root";
        CapabilityBoundingSet = [ "CAP_NET_RAW" ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ dataDir ];
      };
    };

    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 root root -"
    ];

    networking.firewall.allowedTCPPorts = [ 8840 ];
  };
}
