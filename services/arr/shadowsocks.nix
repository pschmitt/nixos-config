{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 8388;
in
{
  sops.secrets."shadowsocks/password" = {
    inherit (config.custom) sopsFile;
  };

  services.shadowsocks = {
    enable = true;
    localAddress = [ "0.0.0.0" ];
    inherit port;
    passwordFile = config.sops.secrets."shadowsocks/password".path;
    mode = "tcp_and_udp";
    encryptionMethod = "chacha20-ietf-poly1305";
  };

  services.monit.config = ''
    check host "shadowsocks" with address ${internalIP}
      group piracy
      depends on mullvad-netns
      restart program = "${pkgs.systemd}/bin/systemctl restart shadowsocks-libev"
      if failed port ${toString port} protocol default for 2 cycles then restart
      if 2 restarts within 6 cycles then alert
  '';

  systemd.services.shadowsocks-libev = {
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
  };

  # Firewall still limits exposure to the tailscale/netbird interfaces.
  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
    }
  ];
}
