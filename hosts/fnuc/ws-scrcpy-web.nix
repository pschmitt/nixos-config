{ config, pkgs, ... }:
let
  # renovate: datasource=docker depName=bilbospocketses/ws-scrcpy-web
  wsScrcpyWebVersion = "0.1.30-beta.205";
  wsScrcpyWebPort = 8000;

  # adb.fnuc.<mesh domain> on every mesh network
  allHosts = config.domains.meshHosts "adb";
  primaryHost = builtins.head allHosts;
  serverAliases = builtins.tail allHosts;
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

  # The app refuses requests whose Host it does not know (DNS-rebinding
  # protection), and reads that list from config.json on the data volume at
  # startup only. Merge it in and leave the app's own settings untouched.
  systemd.services."${config.virtualisation.oci-containers.backend}-ws-scrcpy-web".preStart = ''
    cfg=/var/lib/docker/volumes/wsdata/_data/config.json
    [[ -e "$cfg" ]] || echo '{}' > "$cfg"
    ${pkgs.jq}/bin/jq --argjson hosts '${builtins.toJSON allHosts}' \
      '.allowedHosts = $hosts' "$cfg" > "$cfg.new"
    chown --reference="$cfg" "$cfg.new" || chown 1000:1000 "$cfg.new"
    mv "$cfg.new" "$cfg"
  '';

  services.nginx.virtualHosts."${primaryHost}" = {
    inherit serverAliases;
    enableACME = true;
    forceSSL = true;
    # Authelia is bypassed for requests that come in over the mesh
    authelia = {
      enable = true;
      haIngressBypass = false;
    };

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString wsScrcpyWebPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        # Streams are long-lived
        proxy_read_timeout 1h;
        proxy_send_timeout 1h;
      '';
    };
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
