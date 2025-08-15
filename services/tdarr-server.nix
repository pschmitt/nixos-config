{ pkgs, lib, ... }:
let
  tdarrInterfaces = [
    {
      name = "tailscale";
      iface = "tailscale0";
    }
    {
      name = "netbird";
      iface = "netbird-netbird-io";
    }
  ];
in
{

  imports = [ ./tdarr-node.nix ];

  virtualisation.oci-containers.containers = {
    tdarr = {
      # NOTE the server image is different from the node image!
      image = lib.mkForce "ghcr.io/haveagitgat/tdarr:2.45.01";
      volumes = [ "/srv/tdarr/data/server:/app/server" ];
      environment = {
        internalNode = "true"; # server + node (aio)
        serverIP = lib.mkForce "0.0.0.0";
        webUIPort = "8265";
        auth = "true";
      };
      ports = [
        "127.0.0.1:8265:8265" # web UI port
        "127.0.0.1:8266:8266" # server port

        # NOTE see below for the dynamically publishing of the server port
        # to netbird/ts IPs
        # "100.122.139.168:8266:8266" # netbird
        # "100.114.226.109:8266:8266" # tailscale

        # "127.0.0.1:8267:8267" # Internal node port
      ];
    };
  };

  # Dynamically forward tdarr server port to the netbird/ts IPs
  systemd.services = lib.listToAttrs (
    map (iface: {
      name = "tdarr-socat-${iface.name}";
      value = {
        description = "Socat proxy on ${iface.iface}:8266 → localhost:8266";
        wants = [ "docker-tdarr.service" ];
        after = [ "docker-tdarr.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [
          pkgs.jq
          pkgs.socat
          pkgs.tailscale
        ];
        script = ''
          netbird_ip() {
            # FIXME We should use the pkgs.netbird-netbird-io path here...
            /run/current-system/sw/bin/netbird-netbird-io status --json | \
              jq -er '.netbirdIp | gsub("/.*"; "")'
          }

          case "${iface.iface}" in
            *netbird*)
              LISTEN_IP=$(netbird_ip)
              ;;
            *tailscale*)
              LISTEN_IP=$(tailscale ip -4)
              ;;
            *)
              echo "Unknown interface type: '${iface.name}'" >&2
              exit 2
              ;;
          esac

          if [[ -z "$LISTEN_IP" ]]
          then
            echo "Failed to determine ${iface.name} IP" >&2
            exit 1
          fi

          # NOTE below still attempts to listen on 0.0.0.0:8266
          # socat TCP4-LISTEN:8266,so-bindtodevice=${iface.iface},reuseaddr,fork TCP4:127.0.0.1:8266

          socat "TCP4-LISTEN:8266,bind=''${LISTEN_IP},reuseaddr,fork" TCP4:127.0.0.1:8266
        '';
        serviceConfig = {
          Restart = "always";
          RestartSec = 5;
        };
      };
    }) tdarrInterfaces
  );

}
