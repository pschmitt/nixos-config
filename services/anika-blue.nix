{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  mainHost = "anika.blue";
  serverAliases = [
    "anika-blue.${config.custom.mainDomain}"
    "anika-blue.bergmann-schmitt.de"
    "blue.bergmann-schmitt.de"
  ];
in
{
  imports = [ inputs.anika-blue.nixosModules.default ];

  sops.secrets."anika-blue/secretKey" = {
    inherit (config.custom) sopsFile;
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
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      inherit serverAliases;

      locations."/" = {
        proxyPass = "http://${config.services.anika-blue.bindHost}:${toString config.services.anika-blue.port}";
        recommendedProxySettings = true;
        # proxyWebsockets = true;
      };
    };

    monit.config = lib.mkAfter ''
      check host "anika-blue" with address "anika-blue.${config.custom.mainDomain}"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart anika-blue"
        if failed
          port 443
          protocol https
          with timeout 15 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };
}
