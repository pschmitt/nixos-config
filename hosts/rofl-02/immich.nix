{
  config,
  lib,
  pkgs,
  ...
}:
let
  domains = [
    "brkn.lol"
    "heimat.dev"
  ];
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
in
{
  services.immich = {
    enable = true;
    # NOTE listening on "localhost" leads to immich only listening on IPv6
    host = "127.0.0.1";
    port = 3001;
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
            locations."/".extraConfig = ''
              proxy_pass http://127.0.0.1:${toString config.services.immich.port};
              proxy_set_header Host $host;
              proxy_redirect http:// https://;
              # proxy_http_version 1.1;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection $connection_upgrade;
            '';
          };
        }) hostnames
      );
    in
    {
      virtualHosts = virtualHosts;
    };

  sops.secrets."immich/immich-face-to-album/apiKey" = {
    sopsFile = config.custom.sopsFile;
  };
  sops.secrets."immich/immich-face-to-album/faces/anika" = {
    sopsFile = config.custom.sopsFile;
  };
  sops.secrets."immich/immich-face-to-album/albums/anika" = {
    sopsFile = config.custom.sopsFile;
  };
  sops.templates."immich-face-to-album-anika".content = ''
    API_KEY="${config.sops.placeholder."immich/immich-face-to-album/apiKey"}"
    FACE="${config.sops.placeholder."immich/immich-face-to-album/faces/anika"}"
    ALBUM="${config.sops.placeholder."immich/immich-album-to-album/albums/anika"}"
  '';

  # Define the systemd service
  systemd.services.immich-face-to-album-anika = {
    description = "Run immich-face-to-album for Anika";
    serviceConfig = {
      EnvironmentFile = "${config.sops.templates."immich-face-to-album-anika".path}";
      ExecStart = "${pkgs.immich-face-to-album} --server http://localhost:${toString config.services.immich.port} --key $API_KEY --face $FACE --album $ALBUM";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Define the systemd timer
  systemd.timers.immich-face-to-album-anika = {
    description = "Run immich-face-to-album every hour";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
