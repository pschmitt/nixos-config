{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 9696;
  publicHost = "prowl.arr.${config.domains.main}";
  autheliaConfig = import ../authelia-nginx-config.nix { inherit config; };
in
{
  sops = {
    secrets."prowlarr/apiKey" = {
      inherit (config.custom) sopsFile;
      restartUnits = [ "prowlarr.service" ];
    };
    templates."prowlarr-env" = {
      content = ''
        PROWLARR__AUTH__APIKEY=${config.sops.placeholder."prowlarr/apiKey"}
      '';
      restartUnits = [ "prowlarr.service" ];
    };
  };

  services = {
    prowlarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."prowlarr-env".path ];
    };

    nginx.virtualHosts."${publicHost}" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      extraConfig = autheliaConfig.server;
      locations."/" = {
        proxyPass = "http://${internalIP}:${toString port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = autheliaConfig.location;
      };
    };

    monit.config = ''
      check host "prowlarr" with address ${internalIP}
        group piracy
        depends on mullvad-netns
        restart program = "${pkgs.systemd}/bin/systemctl restart prowlarr"
        if failed port ${toString port} protocol http then restart
        if 5 restarts within 5 cycles then alert
    '';
  };

  fakeHosts.prowlarr.port = port;

  systemd.services.prowlarr = {
    wantedBy = [ "arr.target" ];
    partOf = [ "arr.target" ];
    environment = {
      PROWLARR__SERVER__BINDADDRESS = internalIP;
      # NOTE comment the 2 lines below when doing the initial setup
      PROWLARR__AUTH__METHOD = "Forms";
      PROWLARR__AUTH__REQUIRED = "Enabled";
    };
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
  };

  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
    }
  ];
}
