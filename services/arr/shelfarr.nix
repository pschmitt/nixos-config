{ config, ... }:
let
  port = 5056;
  dataDir = "/mnt/data/srv/shelfarr";
  audiobooksDir = "/mnt/data/audiobooks";
  ebooksDir = "/mnt/data/books";
  transmissionDownloadDir =
    config.services.transmission.settings."download-dir"
      or "${config.services.transmission.home}/Downloads";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 1000 1000 - -"
    "d ${transmissionDownloadDir}/shelfarr 2770 1000 ${config.services.transmission.group} - -"
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
      "${transmissionDownloadDir}/shelfarr:${transmissionDownloadDir}/shelfarr"
      "${audiobooksDir}:${audiobooksDir}"
      "${ebooksDir}:${ebooksDir}"
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
