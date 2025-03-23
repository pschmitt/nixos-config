{ config, ... }:
{
  services.jellyfin = {
    enable = true;
    # dataDir = "/mnt/data/jellyfin";
  };

  services.nginx =
    let
      hostNames = [
        # main
        "media.${config.custom.mainDomain}"
        "tv.${config.custom.mainDomain}"
        "jellyfin.${config.custom.mainDomain}"
        "jelly.${config.custom.mainDomain}"

        # including hostname
        # "jelly.${config.networking.hostName}.${config.custom.mainDomain}"
        # "jellyfin.${config.networking.hostName}.${config.custom.mainDomain}"

        # vpn
        # "media.${config.networking.hostName}.nb.${config.custom.mainDomain}"
        # "media.${config.networking.hostName}.ts.${config.custom.mainDomain}"
      ];
      virtualHosts = builtins.listToAttrs (
        map (hostName: {
          name = hostName;
          value = {
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
        }) hostNames
      );
    in
    {
      virtualHosts = virtualHosts;
    };
}
