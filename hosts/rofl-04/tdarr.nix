{ config, ... }: {

  config.virtualisation.oci-containers.containers = {
    tdarr = {
      image = "ghcr.io/haveagitgat/tdarr_node:latest";
      volumes = [
        # NOTE podman will *not* create these directories on the host
        # "/srv/tdarr/config/tdarr:/app/configs"
        # Below reults in permission error on startup
        # "/srv/tdarr/data/logs:/app/logs"
        # "/srv/tdarr/data/tdarr/transcode_cache:/temp"
        "tdarr-config:/app/configs"
        "tdarr-transcode_cache:/temp"
        "/mnt/data/videos:/media"
      ];
      environment = {
        TZ = "Europe/Berlin";
        PUID = "1000";
        PGID = "1000";
        UMASK_SET = "002";
        nodeName = "${config.networking.hostName}";
        serverIP = "100.122.144.144"; # rofl-02.netbird.cloud
        serverPort = "8266";
        inContainer = "true";
        ffmpegVersion = "6";
      };
    };
  };
}
