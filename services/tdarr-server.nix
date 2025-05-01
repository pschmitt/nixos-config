{ lib, ... }:
{

  imports = [ ./tdarr-node.nix ];

  virtualisation.oci-containers.containers = {
    tdarr = {
      # NOTE the server image is different from the node image!
      image = lib.mkForce "ghcr.io/haveagitgat/tdarr:2.37.01";
      volumes = [ "/srv/tdarr/data/server:/app/server" ];
      environment = {
        internalNode = "true"; # server + node (aio)
        serverIP = lib.mkForce "0.0.0.0";
        webUIPort = "8265";
        auth = "true";
      };
      ports = [
        "127.0.0.1:8265:8265" # web UI port
        # FIXME publish server port netbird/ts IP
        "127.0.0.1:8266:8266" # server port

        # "127.0.0.1:8267:8267" # Internal node port
      ];
    };
  };
}
