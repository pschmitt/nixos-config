{ config, ... }:
{
  virtualisation.oci-containers.containers = {
    tdarr = {
      image = "ghcr.io/haveagitgat/tdarr_node:2.19.01";
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
      autoStart = true;
      environment =
        {
          TZ = "Europe/Berlin";
          PUID = "1000";
          PGID = "1000";
          UMASK_SET = "002";
          nodeName = "${config.networking.hostName}";
          serverIP = "rofl-02.netbird.cloud";
          serverPort = "8266";
          inContainer = "true";
          ffmpegVersion = "6";
        }
        // (
          if config.hardware.nvidia-container-toolkit.enable then
            {
              NVIDIA_VISIBLE_DEVICES = "all";
              NVIDIA_DRIVER_CAPABILITIES = "all";
            }
          else
            { }
        );
      extraOptions = if config.hardware.nvidia-container-toolkit.enable then [ "--gpus=all" ] else [ ];
    };
  };
}
