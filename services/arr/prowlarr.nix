{ config, pkgs, ... }:
let
  internalIP = "10.67.42.2";
  port = 9696;
  publicHost = "prowl.arr.${config.custom.mainDomain}";
  autheliaConfig = import ./authelia.nix { inherit config; };
in
{
  services = {
    prowlarr = {
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
        extraConfig = autheliaConfig.location;
      };
    };

    monit.config = ''
      check host "prowlarr2" with address ${internalIP}
        group piracy
        restart program = "${pkgs.systemd}/bin/systemctl restart prowlarr"
        if failed port ${toString port} protocol http then restart
        if 5 restarts within 5 cycles then alert
    '';
  };

  systemd.services.prowlarr.vpnConfinement = {
    enable = true;
    vpnNamespace = "mullvad";
  };

  vpnNamespaces.mullvad.portMappings = [
    {
      from = 20000 + port;
      to = port;
    }
  ];
}
