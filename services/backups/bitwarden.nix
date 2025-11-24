{ config, ... }:

{
  sops.secrets."bw-backup" = {
    inherit (config.custom) sopsFile;
  };

  virtualisation.oci-containers.containers = {
    bw-backup = {
      image = "ghcr.io/pschmitt/bw-backup:latest";
      autoStart = true;
      environmentFiles = [ config.sops.secrets."bw-backup".path ];
      environment = {
        CRON = "0 0 * * *";
        # DEBUG = "true";
        # START_RIGHT_NOW = "true";
      };
      volumes = [ "/srv/bw-backup:/data" ];
    };
  };
}
