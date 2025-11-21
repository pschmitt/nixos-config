{
  config,
  lib,
  ...
}:
let
  domain = "wish.${config.custom.mainDomain}";
  dataDir = "/mnt/data/srv/wishlist";
  listenPort = 19001;
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 root root - -"
    "d ${dataDir}/uploads 0750 root root - -"
    "d ${dataDir}/data 0750 root root - -"
  ];

  virtualisation.oci-containers.containers.wishlist = {
    image = "ghcr.io/cmintey/wishlist:latest";
    autoStart = true;
    volumes = [
      "${dataDir}/uploads:/usr/src/app/uploads"
      "${dataDir}/data:/usr/src/app/data"
    ];
    environment = {
      ORIGIN = "https://${domain}";
      TOKEN_TIME = "72";
    }
    // lib.optionalAttrs (config.time.timeZone != null) {
      TZ = config.time.timeZone;
    };
    ports = [ "127.0.0.1:${toString listenPort}:3280" ];
  };
}
