{ config, pkgs, ... }:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 8388;
in
{
  sops.secrets."shadowsocks/password" = {
    inherit (config.custom) sopsFile;
  };

  # NOTE To connect, run:
  # , ss-local -s rofl-11.nb.brkn.lol -p 8388 -l 1080 -m chacha20-ietf-poly1305 -k 'SHADOWSOCKS_PASSWORD'
  # curl -x socks5h://127.0.0.1:1080 myip.wtf/json

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
