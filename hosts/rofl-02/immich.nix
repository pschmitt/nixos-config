{
  config,
  lib,
  pkgs,
  ...
}:
let
  domains = [ config.custom.mainDomain ];
  subdomains = [
    "img"
    "immich"
  ];
  hostnames = lib.concatMap (
    domain:
    lib.concatMap (subdomain: [
      "${subdomain}.${domain}"
      "${subdomain}.${config.networking.hostName}.${domain}"
    ]) subdomains
  ) domains;

  # immich-face-to-album
  names = [
    "anika"
    "maya"
  ];

  # Function to generate configurations per name
  generateConfigs = name: {
    sopsSecrets = {
      "immich/immich-face-to-album/faces/${name}" = {
        sopsFile = config.custom.sopsFile;
      };
      "immich/immich-face-to-album/albums/${name}" = {
        sopsFile = config.custom.sopsFile;
      };
    };

    sopsTemplates = {
      "immich-face-to-album-${name}" = {
        content = ''
          API_KEY="${config.sops.placeholder."immich/immich-face-to-album/apiKey"}"
          FACE="${config.sops.placeholder."immich/immich-face-to-album/faces/${name}"}"
          ALBUM="${config.sops.placeholder."immich/immich-face-to-album/albums/${name}"}"
        '';
        owner = config.services.immich.user;
      };
    };

    systemdServices = {
      "immich-face-to-album-${name}" = {
        description = "Run immich-face-to-album for ${lib.toUpper name}";
        after = [ "immich-server.service" ];
        requires = [ "immich-server.service" ];
        serviceConfig = {
          EnvironmentFile = config.sops.templates."immich-face-to-album-${name}".path;
          ExecStart = ''
            ${pkgs.immich-face-to-album}/bin/immich-face-to-album \
            --server http://${config.services.immich.host}:${toString config.services.immich.port} \
            --key "$API_KEY" \
            --face "$FACE" \
            --album "$ALBUM"
          '';
          User = config.services.immich.user;
          Type = "oneshot";
        };
      };
    };

    systemdTimers = {
      "immich-face-to-album-${name}" = {
        description = "Run immich-face-to-album regularly for ${lib.toUpper name}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
        };
      };
    };
  };

  # Generate configurations for all names
  perNameConfigs = map generateConfigs names;

  # Combine configurations
  combinedSopsSecrets = lib.foldl' (acc: cfg: acc // cfg.sopsSecrets) {
    "immich/immich-face-to-album/apiKey" = {
      sopsFile = config.custom.sopsFile;
    };
  } perNameConfigs;

  combinedSopsTemplates = lib.foldl' (acc: cfg: acc // cfg.sopsTemplates) { } perNameConfigs;

  combinedSystemdServices = lib.foldl' (acc: cfg: acc // cfg.systemdServices) { } perNameConfigs;

  combinedSystemdTimers = lib.foldl' (acc: cfg: acc // cfg.systemdTimers) { } perNameConfigs;
in
{
  services.immich = {
    enable = true;
    # package = pkgs.master.immich;
    # NOTE listening on "localhost" leads to immich only listening on IPv6
    host = "127.0.0.1";
    port = 2283;
    mediaLocation = "/mnt/data/srv/immich/media";
  };

  services.nginx =
    let
      virtualHosts = builtins.listToAttrs (
        map (hostname: {
          name = hostname;
          value = {
            enableACME = true;
            # FIXME https://github.com/NixOS/nixpkgs/issues/210807
            acmeRoot = null;
            forceSSL = true;
            locations."/" = {
              proxyPass = "http://${config.services.immich.host}:${toString config.services.immich.port}";
              recommendedProxySettings = true;
              proxyWebsockets = true;
              # Allow uploading large files
              # https://immich.app/docs/FAQ/#why-are-only-photos-and-not-videos-being-uploaded-to-immich
              extraConfig = ''
                client_max_body_size 50000M;
              '';
            };
          };
        }) hostnames
      );
    in
    {
      virtualHosts = virtualHosts;
    };

  # immich-face-to-album
  sops.secrets = combinedSopsSecrets;
  sops.templates = combinedSopsTemplates;
  systemd.services = combinedSystemdServices;
  systemd.timers = combinedSystemdTimers;
}
