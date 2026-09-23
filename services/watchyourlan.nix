{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/srv/watchyourlan/data/wyl";
  listenPort = 8840;
  meshHosts = config.domains.meshHosts "watchyourlan";
  primaryHost = builtins.head meshHosts;
  serverAliases = builtins.tail meshHosts;
  autheliaConfig = import ./authelia-nginx-config.nix {
    inherit config;
    haIngressBypass = false;
  };
in
{
  config = {
    systemd.services.watchyourlan = {
      description = "WatchYourLAN network discovery";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ dataDir ];
      environment = {
        HOST = "0.0.0.0";
        PORT = toString listenPort;
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

    networking.firewall.allowedTCPPorts = [ listenPort ];

    services.nginx.virtualHosts.${primaryHost} = {
      inherit serverAliases;
      enableACME = true;
      acmeRoot = null;
      forceSSL = true;
      extraConfig = autheliaConfig.server;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString listenPort}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = autheliaConfig.location;
      };
    };
  };
}
