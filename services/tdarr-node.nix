{ config, ... }:
{
  # NOTE we can't import this here, since it would produce a weird shizz on rofl-11
  # imports = [
  #   ./nfs/nfs-client-rofl-11.nix
  # ];

  sops = {
    secrets.tdarr-api-key = {
      key = "tdarr/api-key";
    };
    templates.tdarr-api-key.content = ''
      apiKey=${config.sops.placeholder.tdarr-api-key}
    '';
  };

  # Reference: https://docs.tdarr.io/docs/installation/docker/run-compose
  virtualisation.oci-containers.containers = {
    tdarr = {
      image = "ghcr.io/haveagitgat/tdarr_node:2.45.01";
      volumes = [
        # NOTE podman will *not* create these directories on the host
        # "/srv/tdarr/config/tdarr:/app/configs"
        # Below results in permission errors on startup:
        # "/srv/tdarr/data/logs:/app/logs"
        # "/srv/tdarr/data/tdarr/transcode_cache:/temp"
        "tdarr-config:/app/configs"
        "tdarr-transcode_cache:/temp"
        "/mnt/data/videos:/media"
      ];
      autoStart = true;
      environmentFiles = [ config.sops.templates."tdarr-api-key".path ];
      environment = {
        TZ = "Europe/Berlin";
        PUID = "1000";
        PGID = "1000";
        UMASK_SET = "002";
        nodeName = "${config.networking.hostName}";
        serverIP = "rofl-11.${config.domains.tailscale}";
        serverPort = "8266";
        inContainer = "true";
        ffmpegVersion = "7";
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
