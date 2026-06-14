{ config, ... }:
let
  port = 4747;
  dataDir = "/mnt/data/srv/audiobookrequest";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 root root - -"
  ];

  virtualisation.oci-containers.containers.audiobookrequest = {
    image = "docker.io/markbeep/audiobookrequest:latest";
    autoStart = true;
    pull = "always";
    environment = {
      ABR_APP__PORT = toString port;
      TZ = config.time.timeZone;
    };
    volumes = [
      "${dataDir}:/config"
    ];
    extraOptions = [
      "--net=ns:/run/netns/mullvad"
    ];
  };

  arr.services.audiobookrequest = {
    inherit port;
    host = "abr.arr.${config.domains.main}";
    container = "audiobookrequest";
    monit.request = "/";
  };
}
