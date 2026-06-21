{ config, ... }:
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
    monit.request = "/";
  };
}
