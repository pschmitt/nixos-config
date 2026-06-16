{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/srv/esphome";
  # 6052 = device-builder dashboard (HTTP), 6055 = peer-link (remote compile)
  exposedPorts = [
    6052
    6055
  ];
  containerBackend = config.virtualisation.oci-containers.backend;
  containerUnit = "${containerBackend}-esphome.service";

  vpnInterfaces = [
    {
      name = "netbird";
      iface = config.services.netbird.clients.netbird-io.interface;
    }
    {
      name = "tailscale";
      iface = config.services.tailscale.interfaceName;
    }
  ];
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
    # Install and run esphome-device-builder which adds the peer-link server on
    # port 6055 on top of the regular dashboard on port 6052.
    entrypoint = "/bin/bash";
    cmd = [
      "-c"
      "uv pip install esphome-device-builder && exec esphome-device-builder /config"
    ];
    volumes = [
      "${dataDir}/config:/config"
    ];
    ports = map (p: "127.0.0.1:${toString p}:${toString p}") exposedPorts;
  };

  # IPv4: DNAT from VPN interfaces to localhost.
  # Works because route_localnet=1 is set on nb-* and tailscale* by udev rules
  # in the network profiles.
  networking.nftables = {
    enable = true;
    tables."esphome-vpn-redirect" = {
      family = "ip";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          iifname { "nb-*", "tailscale*" } tcp dport { ${
            lib.concatMapStringsSep ", " toString exposedPorts
          } } dnat ip to 127.0.0.1
        }
      '';
    };
  };

  # IPv6: socat on the VPN interface's IPv6 address → 127.0.0.1.
  # Linux has no IPv6 equivalent of route_localnet so DNAT to [::1] is dropped
  # by the kernel; binding socat directly to the interface address sidesteps this.
  systemd.services = lib.listToAttrs (
    lib.concatMap (
      vpn:
      map (port: {
        name = "esphome-socat-ipv6-${vpn.name}-${toString port}";
        value = {
          description = "ESPHome IPv6 proxy on ${vpn.iface}:${toString port} → 127.0.0.1:${toString port}";
          wants = [ containerUnit ];
          after = [ containerUnit ];
          wantedBy = [ "multi-user.target" ];
          path = [
            pkgs.iproute2
            pkgs.gawk
            pkgs.socat
          ];
          script = ''
            LISTEN_IP=$(ip -6 addr show dev "${vpn.iface}" \
              | awk '/inet6 fd/ { split($2, a, "/"); print a[1]; exit }')
            if [[ -z "$LISTEN_IP" ]]; then
              echo "No ULA IPv6 address on ${vpn.iface}" >&2
              exit 1
            fi
            socat "TCP6-LISTEN:${toString port},bind=[''${LISTEN_IP}],reuseaddr,fork" \
              TCP4:127.0.0.1:${toString port}
          '';
          serviceConfig = {
            Restart = "always";
            RestartSec = 5;
          };
        };
      }) exposedPorts
    ) vpnInterfaces
  );

  services.monit.config = lib.mkAfter ''
    check host "esphome" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${containerUnit}"
      if failed
        port 6055
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
