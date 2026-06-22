{
  config,
  lib,
  ...
}:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 8989;
  downloadDir = config.arr.dirs.downloads;
in
{
  sops = {
    secrets."sonarr/apiKey" = config.custom.mkSecret {
      restartUnits = [ "sonarr.service" ];
    };
    templates."sonarr-env" = {
      content = ''
        SONARR__AUTH__APIKEY=${config.sops.placeholder."sonarr/apiKey"}
      '';
      restartUnits = [ "sonarr.service" ];
    };
  };

  users.users.sonarr.extraGroups = [ config.services.transmission.group ];

  systemd.tmpfiles.rules = [
    "d ${downloadDir}/sonarr 2770 ${config.services.transmission.user} ${config.services.sonarr.group} - -"
  ];

  arr.services.sonarr = {
    inherit port;
    host = "son.arr.${config.domains.main}";
    aliases = [ "snr.${config.domains.main}" ];
  };

  services = {
    sonarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."sonarr-env".path ];
    };

    recyclarr.configuration.sonarr.main = {
      # Recyclarr now runs inside the Mullvad namespace with Sonarr.
      base_url = "http://${internalIP}:${toString port}";
      api_key._secret = config.sops.secrets."sonarr/apiKey".path;
      delete_old_custom_formats = true;
      quality_definition.type = "series";
      # "Bad Release - SCR" (CF id 2) was created manually via API with score -10000
      # on all quality profiles to block torrents containing .scr in the title.
      # TODO: add TRaSH custom_formats with trash_ids and assign_scores_to profiles
    };

    # Back up Sonarr config/db alongside the rest of the system
    restic.backups.main.paths = lib.mkIf (!config.hardware.cattle) [
      config.services.sonarr.dataDir
    ];
  };

  systemd.services.sonarr.environment = {
    SONARR__SERVER__BINDADDRESS = internalIP;
    # SSO: delegate UI auth to the reverse proxy (Authelia). The API key still
    # gates /api, so prowlarr/recyclarr keep working over the internal IPs.
    # NOTE comment the 2 lines below when doing the initial setup.
    SONARR__AUTH__METHOD = "External";
    SONARR__AUTH__REQUIRED = "Enabled";
  };
}
