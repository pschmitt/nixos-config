{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 8989;
  publicHost = "son.arr.${config.custom.mainDomain}";
  autheliaConfig = import ./authelia.nix { inherit config; };
in
{
  sops = {
    secrets."sonarr/apiKey" = {
      inherit (config.custom) sopsFile;
      restartUnits = [ "sonarr.service" ];
    };
    templates."sonarr-env" = {
      content = ''
        SONARR__AUTH__APIKEY=${config.sops.placeholder."sonarr/apiKey"}
      '';
      restartUnits = [ "sonarr.service" ];
    };
  };

  services = {
    sonarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."sonarr-env".path ];
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
        extraConfig = autheliaConfig.location;
      };
    };

    monit.config = ''
      check host "sonarr2" with address ${internalIP}
        group piracy
        restart program = "${pkgs.systemd}/bin/systemctl restart sonarr"
        if failed port ${toString port} protocol http then restart
        if 5 restarts within 5 cycles then alert
    '';
  };

  systemd.services.sonarr = {
    environment = {
      SONARR__SERVER__BINDADDRESS = internalIP;
      SONARR__AUTH__METHOD = "Forms";
      SONARR__AUTH__REQUIRED = "Enabled";
    };
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
  };

  vpnNamespaces.mullvad.portMappings = [
    {
      from = 20000 + port;
      to = port;
    }
  ];
}
