{
  config,
  lib,
  pkgs,
  ...
}:
let
  rootDir = "/mnt/data/srv/calibre";
  calibreLibrary = "${rootDir}/library";
  calibreWebAutomatedListen = {
    ip = "127.0.0.1";
    port = 22544;
  };
  calibreWebAutomatedUpstream = "http://${calibreWebAutomatedListen.ip}:${toString calibreWebAutomatedListen.port}";
  calibreWebAutomatedRoot = "${rootDir}/calibre-web-automated";
  calibreWebAutomatedPaths = {
    config = "${calibreWebAutomatedRoot}/config";
    ingest = "/mnt/data/books/ingest";
    plugins = "${calibreWebAutomatedRoot}/plugins";
  };
  calibreWebAutomatedHostnames = [
    "books.${config.domains.main}"
  ];
  calibreWebAutomatedVirtualHosts = builtins.listToAttrs (
    map (hostname: {
      name = hostname;
      value = {
        enableACME = true;
        acmeRoot = null;
        forceSSL = true;
        locations."/" = {
          proxyPass = calibreWebAutomatedUpstream;
          recommendedProxySettings = true;
          proxyWebsockets = true;
        };
      };
    }) calibreWebAutomatedHostnames
  );
  timezone =
    if config ? time && config.time ? timeZone && config.time.timeZone != null then
      config.time.timeZone
    else
      "Etc/UTC";
in
{
  systemd.tmpfiles.rules = [
    "d ${rootDir} 0750 root root - -"
    "d ${calibreWebAutomatedRoot} 0750 ${config.custom.username} ${config.custom.username} - -"
    "d ${calibreLibrary} 0750 ${config.custom.username} ${config.custom.username} - -"
    "d ${calibreWebAutomatedPaths.config} 0750 ${config.custom.username} ${config.custom.username} - -"
    "d ${calibreWebAutomatedPaths.ingest} 0750 ${config.custom.username} ${config.custom.username} - -"
    "d ${calibreWebAutomatedPaths.plugins} 0750 ${config.custom.username} ${config.custom.username} - -"
  ];

  services = {
    calibre-web.enable = lib.mkForce false;
    nginx.virtualHosts = calibreWebAutomatedVirtualHosts;
    monit.config = lib.mkAfter ''
      check host "calibre-web-automated" with address "${builtins.head calibreWebAutomatedHostnames}"
        group services
        restart program = "${pkgs.systemd}/bin/systemctl restart ${config.virtualisation.oci-containers.backend}-calibre-web-automated.service"
        if failed
          port 443
          protocol https
          with timeout 15 seconds
          and certificate valid for 5 days
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  virtualisation.oci-containers.containers.calibre-web-automated = {
    image = "docker.io/crocodilestick/calibre-web-automated:latest";
    autoStart = true;
    ports = [
      "${calibreWebAutomatedListen.ip}:${toString calibreWebAutomatedListen.port}:8083"
    ];
    volumes = [
      "${calibreWebAutomatedPaths.config}:/config"
      "${calibreWebAutomatedPaths.ingest}:/cwa-book-ingest"
      "${calibreLibrary}:/calibre-library"
      "${calibreWebAutomatedPaths.plugins}:/config/.config/calibre/plugins"
    ];
    environment = {
      TZ = timezone;
      NETWORK_SHARE_MODE = "false";
      PUID = "1000";
      PGID = "1000";
    };
  };
}
