{
  config,
  lib,
  pkgs,
  ...
}:
let
  internalPort = 8080;
  listenPort = 24299;
  containerBackend = config.virtualisation.oci-containers.backend;
  monitUnit = "${containerBackend}-clipcascade.service";
  user = "clipcascade";
  group = user;
  stateDir = "/var/lib/${user}";
  dataDir = "${stateDir}/data";
in
{
  users = {
    groups.${group} = { };
    users.${user} = {
      inherit group;
      isSystemUser = true;
      home = stateDir;
      createHome = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 ${user} ${group} - -"
    "d ${dataDir} 0750 ${user} ${group} - -"
  ];

  virtualisation.oci-containers.containers.clipcascade = {
    image = "sathvikrao/clipcascade:latest";
    autoStart = true;
    pull = "always";
    volumes = [ "${dataDir}:/database" ];
    environment = {
      CC_ALLOWED_ORIGINS = "*";
      CC_MAX_MESSAGE_SIZE_IN_MiB = "10";
      CC_P2P_ENABLED = "true";
      CC_PORT = "${toString internalPort}";
      CC_SIGNUP_ENABLED = "false";
    }
    // lib.optionalAttrs (config.time.timeZone != null) {
      TZ = config.time.timeZone;
    };
    ports = [ "0.0.0.0:${toString listenPort}:${toString internalPort}" ];
  };

  services.monit.config = lib.mkAfter ''
    check host "clipcascade" with address "127.0.0.1"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${monitUnit}"
      if failed
        port ${toString listenPort}
        protocol http
        request "/health"
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
