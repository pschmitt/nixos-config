{
  config,
  lib,
  pkgs,
  ...
}:
let
  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  port = 8989;
  publicHost = "son.arr.${config.domains.main}";
  serverAliases = [ "snr.${config.domains.main}" ];
  autheliaConfig = import ../authelia-nginx-config.nix { inherit config; };
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

  services = {
    sonarr = {
      enable = true;
      environmentFiles = [ config.sops.templates."sonarr-env".path ];
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
      check host "sonarr" with address ${internalIP}
        group piracy
        depends on mullvad-netns
        restart program = "${pkgs.systemd}/bin/systemctl restart sonarr"
        if failed port ${toString port}
          protocol http
          request "/ping"
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 5 cycles then alert
    '';
  };

  systemd.services.sonarr = {
    wantedBy = [ "arr.target" ];
    partOf = [ "arr.target" ];
    environment = {
      SONARR__SERVER__BINDADDRESS = internalIP;
      # NOTE comment the 2 lines below when doing the initial setup
      SONARR__AUTH__METHOD = "Forms";
      SONARR__AUTH__REQUIRED = "Enabled";
    };
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
    # Fix for systemd-resolved atomic updates breaking bind mounts
    serviceConfig.TemporaryFileSystem = "/run/systemd/resolve";
  };

  fakeHosts.sonarr.port = port;

  services.recyclarr.configuration.sonarr.main = {
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
  services.restic.backups.main.paths = lib.mkIf (!config.hardware.cattle) [
    config.services.sonarr.dataDir
  ];

  vpnNamespaces.mullvad.portMappings = [
    {
      from = port;
      to = port;
    }
  ];

  systemd.tmpfiles.rules =
    let
      downloadDir =
        config.services.transmission.settings."download-dir"
          or "${config.services.transmission.home}/Downloads";
    in
    [
      "d ${downloadDir}/sonarr 2770 ${config.services.transmission.user} ${config.services.sonarr.group} - -"
    ];
}
