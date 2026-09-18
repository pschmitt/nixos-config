{ config, ... }:
let
  dataDir = "/srv/watchyourlan/data/wyl";
in
{
  virtualisation.oci-containers.containers.watchyourlan = {
    image = "aceberg/watchyourlan:v2";
    autoStart = true;
    extraOptions = [
      "--net=host"
    ];
    environment = {
      HOST = "0.0.0.0";
      PORT = "8840";
      TIMEOUT = "120";
      IFACES = "hass-br0 wlp2s0";
      THEME = "sand";
      COLOR = "dark";
      TZ = config.time.timeZone;
    };
    volumes = [
      "${dataDir}:/data/WatchYourLAN"
    ];
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 root root -"
  ];

  networking.firewall.allowedTCPPorts = [ 8840 ];
}
