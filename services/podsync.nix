{
  config,
  lib,
  ...
}:
let
  dataDir = "/srv/podsync";
  podsyncDataDir = "${dataDir}/data/podsync";
  cookiesDir = "/srv/yt-dlp";
  listenPort = 7637;
  primaryHost = "podsync.${config.domains.main}";
  serverAliases = [
    "podcasts.${config.domains.main}"
    "podsync.${config.networking.hostName}.${config.domains.main}"
  ];
in
{
  sops = {
    secrets = {
      "podsync/youtubeApiKey" = {
        inherit (config.custom) sopsFile;
        restartUnits = [ "${config.virtualisation.oci-containers.backend}-podsync.service" ];
      };
    };
    templates."podsync/config.toml" = {
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "${config.virtualisation.oci-containers.backend}-podsync.service" ];
      content = ''
        [server]
        port = 8080
        hostname = "https://${primaryHost}"

        [storage]
          [storage.local]
          data_dir = "/app/data"

        [tokens]
        youtube = "${config.sops.placeholder."podsync/youtubeApiKey"}"

        [downloader]
        self_update = true
        timeout = 30

        [feeds]
            [feeds.level1techs]
            url = "https://www.youtube.com/channel/UC4w1YQAJMWOz4qtxinq55LQ"
            filters = { title = "(L|Level)1.*Links.*Friends" }
            opml = true
            private_feed = true
            update_period = "1h"
            playlist_sort = "asc"
            page_size = 50
            format = "video"
            max_height = 720
            quality = "high"
            clean = { keep_last = 10 }
            youtube_dl_args = [ "--cookies", "/yt-dlp/cookies.txt" ]

            [feeds.level1linkswithfriends]
            url = "https://www.youtube.com/channel/UCw_X9HgNg2J9p7wRM0FD4bA"
            filters = { title = "Level1 Links With Friends" }
            opml = true
            private_feed = true
            update_period = "1h"
            playlist_sort = "asc"
            page_size = 50
            format = "video"
            max_height = 720
            quality = "high"
            clean = { keep_last = 10 }
            youtube_dl_args = [ "--cookies", "/yt-dlp/cookies.txt" ]
      '';
    };
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir}         0750 root root - -"
    "d ${podsyncDataDir}  0750 root root - -"
    "d ${cookiesDir}      0750 root pinchflat - -"
  ];

  virtualisation.oci-containers.containers.podsync = {
    autoStart = true;
    image = "ghcr.io/mxpv/podsync:nightly";
    pull = "always";
    ports = [
      "127.0.0.1:${toString listenPort}:8080"
    ];
    volumes = [
      "${podsyncDataDir}:/app/data"
      "${cookiesDir}:/yt-dlp"
      "${config.sops.templates."podsync/config.toml".path}:/app/config.toml:ro"
    ];
  };

  services.nginx.virtualHosts."${primaryHost}" = {
    inherit serverAliases;
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString listenPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "podsync" with address "127.0.0.1"
      group container-services
      restart program = "${config.virtualisation.oci-containers.backend}-podsync.service"
      if failed
        port ${toString listenPort}
        protocol http
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
