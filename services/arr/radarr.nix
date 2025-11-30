{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 7878;
  publicHost = "rad.arr.${config.custom.mainDomain}";
  autheliaConfig = import ./authelia.nix { inherit config; };
in
{
  sops = {
    secrets."radarr/apiKey" = {
      inherit (config.custom) sopsFile;
      restartUnits = [ "radarr.service" ];
    };
    templates."radarr-env" = {
      content = ''
        RADARR__AUTH__APIKEY=${config.sops.placeholder."radarr/apiKey"}
      '';
      restartUnits = [ "radarr.service" ];
    };
  };

  services = {
    radarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."radarr-env".path ];
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
      check host "radarr2" with address ${internalIP}
        group piracy
        restart program = "${pkgs.systemd}/bin/systemctl restart radarr"
        if failed port ${toString port} protocol http then restart
        if 5 restarts within 5 cycles then alert
    '';
  };

  systemd.services.radarr = {
    environment = {
      RADARR__SERVER__BINDADDRESS = internalIP;
      RADARR__AUTH__METHOD = "Forms";
      RADARR__AUTH__REQUIRED = "Enabled";
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
