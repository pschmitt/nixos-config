{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/srv/esphome";
  esphomePort = 6055;
  containerBackend = config.virtualisation.oci-containers.backend;
  containerUnit = "${containerBackend}-esphome.service";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir}        0750 root root - -"
    "d ${dataDir}/config 0750 root root - -"
  ];

  virtualisation.oci-containers.containers.esphome = {
    autoStart = true;
    image = "esphome/esphome:latest";
    pull = "always";
    volumes = [
      "${dataDir}/config:/config"
    ];
    ports = [
      "127.0.0.1:${toString esphomePort}:${toString esphomePort}"
      "[::1]:${toString esphomePort}:${toString esphomePort}"
    ];
  };

  # DNAT incoming VPN traffic on port 6055 to the container on localhost.
  # route_localnet is already enabled for nb-* and tailscale* by the
  # network profiles via udev rules.
  networking.nftables = {
    enable = true;
    tables."esphome-vpn-redirect" = {
      family = "inet";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          meta nfproto ipv4 iifname { "nb-*", "tailscale*" } tcp dport ${toString esphomePort} dnat ip to 127.0.0.1:${toString esphomePort}
          meta nfproto ipv6 iifname { "nb-*", "tailscale*" } tcp dport ${toString esphomePort} dnat ip6 to [::1]:${toString esphomePort}
        }
      '';
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "esphome" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${containerUnit}"
      if failed
        port ${toString esphomePort}
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
