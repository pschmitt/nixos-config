{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 7878;
  publicHost = "rad.arr.${config.custom.mainDomain}";
  serverAliases = [ "rdr.${config.custom.mainDomain}" ];
  autheliaConfig = import ../authelia-nginx-config.nix { inherit config; };
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

  users.users.radarr.extraGroups = [ "media" ];

  services = {
    radarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."radarr-env".path ];
    };

    nginx.virtualHosts."${publicHost}" = {
      inherit serverAliases;
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
      check host "radarr" with address ${internalIP}
        group piracy
        depends on mullvad-netns
        restart program = "${pkgs.systemd}/bin/systemctl restart radarr"
        if failed port ${toString port} protocol http then restart
        if 5 restarts within 5 cycles then alert
    '';
  };

  fakeHosts.radarr.port = port;

  systemd.services.radarr = {
    environment = {
      RADARR__SERVER__BINDADDRESS = internalIP;
      # NOTE comment the 2 lines below when doing the initial setup
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
      from = port;
      to = port;
    }
  ];
}
