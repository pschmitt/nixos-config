{
  config,
  lib,
  ...
}:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 7878;
  downloadDir = config.arr.dirs.downloads;
in
{
  sops = {
    secrets."radarr/apiKey" = config.custom.mkSecret {
      restartUnits = [ "radarr.service" ];
    };
    templates."radarr-env" = {
      content = ''
        RADARR__AUTH__APIKEY=${config.sops.placeholder."radarr/apiKey"}
      '';
      restartUnits = [ "radarr.service" ];
    };
  };

  users.users.radarr.extraGroups = [ config.services.transmission.group ];

  systemd.tmpfiles.rules = [
    "d ${downloadDir}/radarr 2770 ${config.services.transmission.user} ${config.services.radarr.group} - -"
  ];

  arr.services.radarr = {
    inherit port;
    host = "rad.arr.${config.domains.main}";
    aliases = [ "rdr.${config.domains.main}" ];
  };

  services = {
    radarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."radarr-env".path ];
    };

    recyclarr.configuration.radarr.main = {
      # Recyclarr now runs inside the Mullvad namespace with Radarr.
      base_url = "http://${internalIP}:${toString port}";
      api_key._secret = config.sops.secrets."radarr/apiKey".path;
      delete_old_custom_formats = true;
      quality_definition.type = "movie";
      # "Bad Release - SCR" (CF id 1) was created manually via API with score -10000
      # on all quality profiles to block torrents containing .scr in the title.
      # TODO: add TRaSH custom_formats with trash_ids and assign_scores_to profiles
    };

    # Back up Radarr config/db alongside the rest of the system
    restic.backups.main.paths = lib.mkIf (!config.hardware.cattle) [
      config.services.radarr.dataDir
    ];
  };

  systemd.services.radarr.environment = {
    RADARR__SERVER__BINDADDRESS = internalIP;
    # SSO: delegate UI auth to the reverse proxy (Authelia). The API key still
    # gates /api, so prowlarr/recyclarr keep working over the internal IPs.
    # NOTE comment the 2 lines below when doing the initial setup.
    RADARR__AUTH__METHOD = "External";
    RADARR__AUTH__REQUIRED = "Enabled";
  };
}
