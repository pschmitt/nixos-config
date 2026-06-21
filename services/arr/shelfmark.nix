{ config, lib, ... }:
let
  port = 8084;
  dataDir = "/mnt/data/srv/shelfmark";
  inherit (config.arr.dirs) audiobooks books downloads;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 1000 1000 - -"
    "d ${downloads}/shelfmark 2770 1000 ${config.services.transmission.group} - -"
  ];

  virtualisation.oci-containers.containers.shelfmark = {
    image = "ghcr.io/calibrain/shelfmark:latest";
    autoStart = true;
    pull = "always";
    environment = {
      FLASK_PORT = toString port;
      PUID = "1000";
      PGID = "1000";
      TZ = config.time.timeZone;
      # Served inside the HA sidebar via the `ingress` integration's proxy at a
      # stable sub-path; emit asset/API URLs under that prefix so the SPA loads.
      # Must match the ingress `url` path in HA's config.d/ingress.yaml.
      URL_BASE = "/api/ingress/shelfmark";
      # SSO: trust the X-Auth-User header that nginx sets (see the vhost config).
      AUTH_METHOD = "proxy";
      PROXY_AUTH_USER_HEADER = "X-Auth-User";
    };
    volumes = [
      "${dataDir}:/config"
      "${books}:${books}"
      "${audiobooks}:${audiobooks}"
      "${downloads}/shelfmark:${downloads}/shelfmark"
    ];
    extraOptions = [
      "--net=ns:/run/netns/mullvad"
    ];
  };

  arr.services.shelfmark = {
    inherit port;
    host = "shelfmark.arr.${config.domains.main}";
    aliases = [ "shelf.arr.${config.domains.main}" ];
    container = "shelfmark";
    monit.request = "/api/ingress/shelfmark/";
  };

  services.nginx.virtualHosts."shelfmark.arr.${config.domains.main}".locations = {
    # URL_BASE makes shelfmark serve only under /api/ingress/shelfmark, so a plain
    # visit to shelf.arr.brkn.lol/ would 404. Redirect the root to the prefix so
    # direct access "just works" (Authelia still gates it via the / location).
    "= /".return = "302 /api/ingress/shelfmark/";

    # SSO for shelfmark's AUTH_METHOD=proxy: set X-Auth-User to a trusted value.
    # HA ingress requests carry the Authelia-bypass token, so trust the username
    # HA injected ($username -> X-Auth-User). Everyone else gets Authelia's
    # verified user; a client-supplied X-Auth-User is always overridden here, so
    # it cannot be spoofed. Unauthenticated LAN access yields an empty user and
    # falls back to shelfmark's own login.
    "/".extraConfig = lib.mkAfter ''
      set $shelfmark_user $user;
      if ($authelia_ha_bypass) {
        set $shelfmark_user $http_x_auth_user;
      }
      proxy_set_header X-Auth-User $shelfmark_user;
    '';
  };
}
