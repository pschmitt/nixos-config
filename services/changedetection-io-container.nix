{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "changes.${config.domains.main}";
  dataDir = "/mnt/data/srv/changedetection-io";
  listenPort = 24264;
  networkName = "changedetection-io";
  containerBackend = config.virtualisation.oci-containers.backend;
  monitUnit = "${containerBackend}-changedetection-io.service";
  runtimePkg =
    if containerBackend == "docker" then
      pkgs.docker
    else if containerBackend == "podman" then
      pkgs.podman
    else
      throw "Unsupported OCI container backend: ${containerBackend}";
  runtimeBin = "${runtimePkg}/bin/${containerBackend}";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 root root - -"
  ];

  virtualisation.oci-containers.containers = {
    changedetection-io-playwright = {
      image = "dgtlmoon/sockpuppetbrowser:latest";
      autoStart = true;
      hostname = "changedetection-io-playwright";
      capabilities.SYS_ADMIN = true;
      environment = {
        SCREEN_WIDTH = "1920";
        SCREEN_HEIGHT = "1024";
        SCREEN_DEPTH = "16";
        MAX_CONCURRENT_CHROME_PROCESSES = "10";
      };
      networks = [ networkName ];
    };

    changedetection-io = {
      image = "ghcr.io/dgtlmoon/changedetection.io:latest";
      autoStart = true;
      hostname = "changedetection";
      dependsOn = [ "changedetection-io-playwright" ];
      volumes = [ "${dataDir}:/datastore" ];
      environment = {
        BASE_URL = "https://${domain}";
        DISABLE_VERSION_CHECK = "true";
        PLAYWRIGHT_DRIVER_URL = "ws://changedetection-io-playwright:3000";
        PORT = "5000";
      }
      // lib.optionalAttrs (config.time.timeZone != null) {
        TZ = config.time.timeZone;
      };
      ports = [ "127.0.0.1:${toString listenPort}:5000" ];
      networks = [ networkName ];
    };
  };

  systemd.services."${containerBackend}-changedetection-io-playwright".preStart = ''
    if ! ${runtimeBin} network inspect ${networkName} >/dev/null 2>&1; then
      ${runtimeBin} network create ${networkName}
    fi
  '';

  services.monit.config = lib.mkAfter ''
    check host "changedetection-io" with address "127.0.0.1"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${monitUnit}"
      if failed
        port ${toString listenPort}
        protocol http
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
