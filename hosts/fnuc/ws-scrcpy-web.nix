{ config, ... }:
let
  # renovate: datasource=docker depName=bilbospocketses/ws-scrcpy-web
  wsScrcpyWebVersion = "0.1.30-beta.205";
  wsScrcpyWebPort = 8000;
in
{
  virtualisation.oci-containers.containers.ws-scrcpy-web = {
    image = "bilbospocketses/ws-scrcpy-web:${wsScrcpyWebVersion}";
    autoStart = true;
    # Loopback only: the app is reached through an SSH tunnel, never directly
    ports = [ "127.0.0.1:${toString wsScrcpyWebPort}:8000" ];
    # Named volume: config.json, the SQLite store and the downloaded adb
    volumes = [ "wsdata:/data" ];
  };

  services.monit.checks.ws-scrcpy-web = {
    type = "host";
    address = "127.0.0.1";
    group = "container-services";
    restartUnit = "${config.virtualisation.oci-containers.backend}-ws-scrcpy-web.service";
    conditions = ''
        with timeout 180 seconds
      if failed
        port ${toString wsScrcpyWebPort}
        protocol http
        with timeout 90 seconds
        for 3 cycles
      then restart
      if 3 restarts within 15 cycles then alert
    '';
  };
}
