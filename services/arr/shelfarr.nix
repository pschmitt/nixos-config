{ config, ... }:
let
  port = 5056;
  dataDir = "/mnt/data/srv/shelfarr";
  inherit (config.arr.dirs) audiobooks books downloads;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 1000 1000 - -"
    "d ${downloads}/shelfarr 2770 1000 ${config.services.transmission.group} - -"
  ];

  virtualisation.oci-containers.containers.shelfarr = {
    image = "ghcr.io/pedro-revez-silva/shelfarr:latest";
    autoStart = true;
    pull = "always";
    environment = {
      HTTP_PORT = toString port;
      TZ = config.time.timeZone;
    };
    volumes = [
      "${dataDir}:/rails/storage"
      "${downloads}/shelfarr:${downloads}/shelfarr"
      "${audiobooks}:${audiobooks}"
      "${books}:${books}"
    ];
    extraOptions = [
      "--net=ns:/run/netns/mullvad"
    ];
  };

  arr.services.shelfarr = {
    inherit port;
    host = "shelf.arr.${config.domains.main}";
    container = "shelfarr";
    monit.request = "/";
  };
}
