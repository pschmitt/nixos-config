{
  config,
  lib,
  ...
}:
let
  hostnames = [
    # main
    "media.${config.custom.mainDomain}"
    "tv.${config.custom.mainDomain}"
    "jellyfin.${config.custom.mainDomain}"
    "jelly.${config.custom.mainDomain}"
  ];
  primaryHost = builtins.head hostnames;
  serverAliases = lib.remove primaryHost hostnames;

  jellyseerHost = "jellyseer.${config.custom.mainDomain}";
in
{
  services = {
    jellyfin = {
      enable = true;
      # dataDir = "/mnt/data/jellyfin";
    };

    jellyseer = {
      enable = true;
      # configDir = "/var/lib/jellyseerr/config";

    };

    nginx.virtualHosts."${primaryHost}" = {
      inherit serverAliases;
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8096";
        recommendedProxySettings = true;
        proxyWebsockets = true;
      };
    };

    nginx.virtualHosts."${jellyseerHost}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.jellyseer.port}";
        recommendedProxySettings = true;
        proxyWebsockets = true;
      };
    };
  };
}
