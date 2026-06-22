{ config, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 9696;
in
{
  sops = {
    secrets."prowlarr/apiKey" = config.custom.mkSecret {
      restartUnits = [ "prowlarr.service" ];
    };
    templates."prowlarr-env" = {
      content = ''
        PROWLARR__AUTH__APIKEY=${config.sops.placeholder."prowlarr/apiKey"}
      '';
      restartUnits = [ "prowlarr.service" ];
    };
  };

  arr.services.prowlarr = {
    inherit port;
    host = "prowl.arr.${config.domains.main}";
  };

  services.prowlarr = {
    enable = true;
    environmentFiles = [ config.sops.templates."prowlarr-env".path ];
  };

  systemd.services.prowlarr.environment = {
    PROWLARR__SERVER__BINDADDRESS = internalIP;
    # SSO: delegate UI auth to the reverse proxy (Authelia). The API key still
    # gates /api, so sonarr/radarr/recyclarr keep working over the internal IPs.
    # NOTE comment the 2 lines below when doing the initial setup.
    PROWLARR__AUTH__METHOD = "External";
    PROWLARR__AUTH__REQUIRED = "Enabled";
  };
}
