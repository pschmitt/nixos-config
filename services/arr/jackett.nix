{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 9117;
  publicHost = "jackett.arr.${config.domains.main}";
  autheliaConfig = import ../authelia-nginx-config.nix { inherit config; };
in
{
  services = {
    jackett = {
      enable = true;
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
      check host "jackett" with address ${internalIP}
        group piracy
        depends on mullvad-netns
        restart program = "${pkgs.systemd}/bin/systemctl restart jackett"
        if failed port ${toString port} protocol http then restart
        if 5 restarts within 5 cycles then alert
    '';
  };

  fakeHosts.jackett.port = port;

  systemd.services.jackett = {
    wantedBy = [ "arr.target" ];
    partOf = [ "arr.target" ];
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
    # Fix for systemd-resolved atomic updates breaking bind mounts
    serviceConfig.TemporaryFileSystem = "/run/systemd/resolve";
  };

  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
    }
  ];
}
