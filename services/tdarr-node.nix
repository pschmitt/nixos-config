{ config, ... }:
{
  # NOTE we can't import this here, since it would produce a weird shizz on rofl-07
  # imports = [ ./nfs/nfs-client-rofl-07.nix ];

  sops = {
    secrets.tdarr-api-key = {
      key = "tdarr/api-key";
    };
    templates.tdarr-api-key.content = ''
      apiKey=${config.sops.placeholder.tdarr-api-key}
    '';
  };

  virtualisation.oci-containers.containers = {
    tdarr = {
      image = "ghcr.io/haveagitgat/tdarr_node:2.37.01";
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
      environment =
        {
          TZ = "Europe/Berlin";
          PUID = "1000";
          PGID = "1000";
          UMASK_SET = "002";
          nodeName = "${config.networking.hostName}";
          serverIP = "rofl-07.ts.${config.custom.mainDomain}";
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
