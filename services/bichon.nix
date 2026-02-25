{
  config,
  lib,
  ...
}:
let
  listenPort = 15630;
  containerPort = 15630;
  dataDir = "/srv/bichon/data";
  containerUid = 1000;
  containerGid = 1000;
  # renovate: datasource=docker depName=rustmailer/bichon
  bichonVersion = "0.3.7";
in
{
  systemd.tmpfiles.rules = [
    "d /srv/bichon 0750 root root - -"
    "d ${dataDir} 0750 ${toString containerUid} ${toString containerGid} - -"
  ];

  virtualisation.oci-containers.containers.bichon = {
    image = "rustmailer/bichon:${bichonVersion}";
    autoStart = true;
    pull = "always";
    user = "${toString containerUid}:${toString containerGid}";
    ports = [
      "127.0.0.1:${toString listenPort}:${toString containerPort}"
    ];
    volumes = [
      "${dataDir}:/data"
    ];
    environment = {
      BICHON_ROOT_DIR = "/data";
      BICHON_LOG_LEVEL = "info";
    }
    // lib.optionalAttrs (config.time.timeZone != null) {
      TZ = config.time.timeZone;
    };
  };
}
