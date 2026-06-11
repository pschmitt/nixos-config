{
  config,
  lib,
  pkgs,
  ...
}:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 7878;
  publicHost = "rad.arr.${config.domains.main}";
  serverAliases = [ "rdr.${config.domains.main}" ];
  autheliaConfig = import ../authelia-nginx-config.nix { inherit config; };
  downloadDir =
    config.services.transmission.settings."download-dir"
      or "${config.services.transmission.home}/Downloads";
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

  services = {
    radarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."radarr-env".path ];
    };

    nginx.virtualHosts."${publicHost}" = {
      inherit serverAliases;
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      extraConfig = autheliaConfig.server;
      locations."/" = {
        proxyPass = "http://${internalIP}:${toString port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = autheliaConfig.location;
      };
    };

    monit.config = ''
      check host "radarr" with address ${internalIP}
        group piracy
        depends on mullvad-netns
        restart program = "${pkgs.systemd}/bin/systemctl restart radarr"
        if failed port ${toString port}
          protocol http
          request "/ping"
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 5 cycles then alert
    '';
  };

  fakeHosts.radarr.port = port;

  services.recyclarr.configuration.radarr.main = {
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
  services.restic.backups.main.paths = lib.mkIf (!config.hardware.cattle) [
    config.services.radarr.dataDir
  ];

  systemd.services.radarr = {
    wantedBy = [ "arr.target" ];
    partOf = [ "arr.target" ];
    environment = {
      RADARR__SERVER__BINDADDRESS = internalIP;
      # NOTE comment the 2 lines below when doing the initial setup
      RADARR__AUTH__METHOD = "Forms";
      RADARR__AUTH__REQUIRED = "Enabled";
    };
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
    # Fix for systemd-resolved atomic updates breaking bind mounts
    serviceConfig.TemporaryFileSystem = "/run/systemd/resolve";
  };

  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
    }
  ];
}
