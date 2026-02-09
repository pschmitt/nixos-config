{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/srv/podsync";
  podsyncDataDir = "${dataDir}/data/podsync";
  cookiesDir = "/srv/yt-dlp";
  listenPort = 7637;
  containerPort = 8080;
  primaryHost = "podsync.${config.domains.main}";
  serverAliases = [
    "podcasts.${config.domains.main}"
    "podsync.${config.networking.hostName}.${config.domains.main}"
  ];
  feedDefaults = {
    opml = true;
    private_feed = true;
    update_period = "1h";
    playlist_sort = "asc";
    page_size = 10;
    format = "video";
    max_height = 720;
    quality = "high";
    clean = {
      keep_last = 10;
    };
    youtube_dl_args = [
      "--cookies"
      "/yt-dlp/cookies.txt"
    ];
  };
  podsyncConfig = {
    server = {
      port = containerPort;
      hostname = "https://${primaryHost}";
    };
    storage = {
      local = {
        data_dir = "/app/data";
      };
    };
    downloader = {
      self_update = true;
      timeout = 30;
    };
    feeds = {
      level1linkswithfriends = feedDefaults // {
        # url = "https://www.youtube.com/channel/UCw_X9HgNg2J9p7wRM0FD4bA";
        url = "https://www.youtube.com/playlist?list=PLcq4cFFv50gtSUtKIRKv7ssIrWgV6nQg0";
        # filters = {
        #   title = "The Level1 Links With Friends";
        # };
      };
      meinungsmache = feedDefaults // {
        url = "https://www.youtube.com/playlist?list=PL2BEOktlDRHxwsLFu7HlvaDI3Zy7MErFs";
      };
    };
  };
  tomlFormat = pkgs.formats.toml { };
  podsyncConfigFile = tomlFormat.generate "podsync.toml" podsyncConfig;
in
{
  sops = {
    secrets = {
      "podsync/youtubeApiKey" = {
        inherit (config.custom) sopsFile;
        restartUnits = [ "${config.virtualisation.oci-containers.backend}-podsync.service" ];
      };
    };
    templates."podsync/env" = {
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "${config.virtualisation.oci-containers.backend}-podsync.service" ];
      content = ''
        PODSYNC_YOUTUBE_API_KEY=${config.sops.placeholder."podsync/youtubeApiKey"}
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
      "127.0.0.1:${toString listenPort}:${toString containerPort}"
    ];
    volumes = [
      "${podsyncDataDir}:/app/data"
      "${cookiesDir}:/yt-dlp"
      "${podsyncConfigFile}:/app/config.toml:ro"
    ];
    environmentFiles = [
      config.sops.templates."podsync/env".path
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
