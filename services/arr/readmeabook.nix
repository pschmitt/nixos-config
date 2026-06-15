{ config, ... }:
let
  port = 3030;
  dataDir = "/mnt/data/srv/readmeabook";
  inherit (config.arr.dirs) audiobooks downloads;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 1000 1000 - -"
    "d ${dataDir}/config 0750 1000 1000 - -"
    "d ${dataDir}/postgres 0750 1000 1000 - -"
    "d ${dataDir}/redis 0750 1000 1000 - -"
    "d ${downloads}/readmeabook 2770 1000 ${config.services.transmission.group} - -"
  ];

  virtualisation.oci-containers.containers.readmeabook = {
    image = "ghcr.io/kikootwo/readmeabook:latest";
    autoStart = true;
    pull = "always";
    environment = {
      TZ = config.time.timeZone;
      PUBLIC_URL = "https://rmab.arr.${config.domains.main}";
    };
    volumes = [
      "${dataDir}/config:/app/config"
      "${dataDir}/postgres:/var/lib/postgresql/data"
      "${dataDir}/redis:/var/lib/redis"
      "${downloads}/readmeabook:/downloads"
      "${audiobooks}:/media"
    ];
    extraOptions = [
      "--net=ns:/run/netns/mullvad"
    ];
  };

  arr.services.readmeabook = {
    inherit port;
    host = "rmab.arr.${config.domains.main}";
    container = "readmeabook";
    monit.request = "/";
  };
}
