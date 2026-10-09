{
  config,
  inputs,
  ...
}:
let
  mainHost = "anika.blue";
  serverAliases = [
    "anika-blue.${config.domains.main}"
    "anika-blue.bergmann-schmitt.de"
    "blue.bergmann-schmitt.de"
  ];
in
{
  imports = [ inputs.anika-blue.nixosModules.default ];

  sops.secrets."anika-blue/secretKey" = config.sops.mkHostSecret {
  };

  services = {
    anika-blue = {
      enable = true;
      debug = false;
      bindHost = "0.0.0.0";
      port = 26452;
      dataDir = "/var/lib/anika-blue";
      secretKeyFile = config.sops.secrets."anika-blue/secretKey".path;
    };

    nginx.virtualHosts."${mainHost}" = {
      enableACME = true;
      forceSSL = true;
      inherit serverAliases;

      locations."/" = {
        proxyPass = "http://${config.services.anika-blue.bindHost}:${toString config.services.anika-blue.port}";
        recommendedProxySettings = true;
        # proxyWebsockets = true;
      };
    };

    monit.checks = {
      anika-blue = {
        type = "host";
        address = "anika-blue.${config.domains.main}";
        group = "services";
        restartUnit = "anika-blue";
        conditions = ''
          if failed
            port 443
            protocol https
            with timeout 15 seconds
            for 3 cycles
          then restart
          if 3 restarts within 15 cycles then alert
        '';
      };
    };
  };
}
