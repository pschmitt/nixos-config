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

  # Trusted username for shelfmark's AUTH_METHOD=proxy. A map (not a `set`) so it
  # is evaluated lazily at proxy time, AFTER auth_request_set populates $user — a
  # plain `set` runs in the rewrite phase before $user exists and would send an
  # empty header. HA ingress requests carry the bypass token, so trust the
  # username HA injected ($http_x_auth_user); everyone else gets Authelia's
  # verified Remote-User ($user). A client-supplied X-Auth-User is always
  # overridden, so it cannot be spoofed; unauthenticated access yields an empty
  # user and falls back to shelfmark's own login.
  services.nginx.appendHttpConfig = ''
    map $authelia_ha_bypass $shelfmark_user {
      "1"     $http_x_auth_user;
      default $user;
    }
  '';

  services.nginx.virtualHosts."shelfmark.arr.${config.domains.main}".locations = {
    # URL_BASE makes shelfmark serve only under /api/ingress/shelfmark, so a plain
    # visit to shelf.arr.brkn.lol/ would 404. Redirect the root to the prefix so
    # direct access "just works" (Authelia still gates it via the / location).
    "= /".return = "302 /api/ingress/shelfmark/";

    "/".extraConfig = lib.mkAfter ''
      proxy_set_header X-Auth-User $shelfmark_user;
    '';
  };
}
