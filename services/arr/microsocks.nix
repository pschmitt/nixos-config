{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 1080;
in
{
  services.microsocks = {
    enable = true;
    ip = "0.0.0.0";
    inherit port;
  };

  services.monit.config = ''
    check host "microsocks" with address ${internalIP}
      group piracy
      depends on mullvad-netns
      restart program = "${pkgs.systemd}/bin/systemctl restart microsocks"
      if failed port ${toString port}
        protocol default
        with timeout 15 seconds
        for 3 cycles
      then restart
      if 3 restarts within 5 cycles then alert
  '';

  systemd.services.microsocks = {
    wantedBy = [ "arr.target" ];
    partOf = [ "arr.target" ];
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
    # Fix for systemd-resolved atomic updates breaking bind mounts
    serviceConfig.TemporaryFileSystem = "/run/systemd/resolve";
  };

  # Firewall still limits exposure to the tailscale/netbird interfaces.
  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
    }
  ];
}
