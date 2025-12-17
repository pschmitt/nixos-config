{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 8191;
in
{
  services.flaresolverr = {
    enable = true;
    package = pkgs.flaresolverr;
    inherit port;
    openFirewall = false;
  };

  services.monit.config = ''
    check host "flaresolverr" with address ${internalIP}
      group piracy
      depends on mullvad-netns
      restart program = "${pkgs.systemd}/bin/systemctl restart flaresolverr"
      if failed port ${toString port} protocol http then restart
      if 5 restarts within 5 cycles then alert
  '';

  fakeHosts.flaresolverr.port = port;

  systemd.services.flaresolverr = {
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
