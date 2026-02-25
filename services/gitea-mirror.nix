{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/srv/gitea-mirror";
  listenPort = 54439;
  containerBackend = config.virtualisation.oci-containers.backend;
  serviceUnit = "${containerBackend}-gitea-mirror.service";
  containerUid = 1000;
  containerGid = 1000;
  inherit (config.networking) hostName;
  mainHost = "mirror.${config.domains.main}";
  netbirdHost = "${hostName}.${config.domains.netbird}";
  tailscaleHost = "${hostName}.${config.domains.tailscale}";
  vpnHost = "${hostName}.${config.domains.vpn}";
  primaryOrigin = "https://${mainHost}";
  trustedOrigins = lib.strings.concatStringsSep "," [
    primaryOrigin
    "http://${netbirdHost}:${toString listenPort}"
    "http://${tailscaleHost}:${toString listenPort}"
    "http://${vpnHost}:${toString listenPort}"
  ];
  mirrorHealthCheckScript = pkgs.writeShellScript "gitea-mirror-health-check" ''
    if ! health="$(${pkgs.curl}/bin/curl --silent --show-error --fail --max-time 10 "http://127.0.0.1:${toString listenPort}/api/health")"
    then
      printf '%s\n' 'fetch_failed path=/api/health' >&2
      exit 1
    fi

    if ! ${pkgs.jq}/bin/jq -e '
      .status == "ok"
      and .database.connected == true
      and .recovery.status == "healthy"
      and .recovery.inProgress == false
    ' <<<"$health" >/dev/null
    then
      details="$(${pkgs.jq}/bin/jq -r '
        "status=\(.status // "null")",
        "dbConnected=\(.database.connected // "null")",
        "recoveryStatus=\(.recovery.status // "null")",
        "recoveryInProgress=\(.recovery.inProgress // "null")",
        "timestamp=\(.timestamp // "null")",
        "version=\(.version // "null")"
      ' <<<"$health" 2>/dev/null || printf '%s' 'invalid_health_payload')"
      printf 'health_assertion_failed\n%s\n' "$details" >&2
      exit 1
    fi
  '';
in
{
  sops.secrets = {
    "gitea-mirror/env" = {
      inherit (config.custom) sopsFile;
      restartUnits = [ "${config.virtualisation.oci-containers.backend}-gitea-mirror.service" ];
    };
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir}      0750 ${toString containerUid} ${toString containerGid} - -"
    "d ${dataDir}/data 0750 ${toString containerUid} ${toString containerGid} - -"
  ];

  # TODO There's a nix module for gitea-mirror!
  # https://github.com/RayLabsHQ/gitea-mirror/blob/main/docs/NIX_DEPLOYMENT.md
  virtualisation.oci-containers.containers.gitea-mirror = {
    autoStart = true;
    image = "ghcr.io/raylabshq/gitea-mirror:latest";
    pull = "always";
    user = "${toString containerUid}:${toString containerGid}";
    ports = [
      "127.0.0.1:${toString listenPort}:${toString listenPort}"
    ];
    volumes = [
      "${dataDir}/data:/app/data"
    ];
    environmentFiles = [
      config.sops.secrets."gitea-mirror/env".path
    ];
    environment = {
      BETTER_AUTH_URL = primaryOrigin;
      BETTER_AUTH_TRUSTED_ORIGINS = trustedOrigins;
      NODE_ENV = "production";
      DATABASE_URL = "file:data/gitea-mirror.db";
      HOST = "0.0.0.0";
      PORT = toString listenPort;
    };
  };

  services.nginx.virtualHosts."${mainHost}" = {
    enableACME = true;
    # FIXME https://github.com/NixOS/nixpkgs/issues/210807
    acmeRoot = null;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString listenPort}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "gitea-mirror" with address "127.0.0.1"
      group container-services
      restart program = "${pkgs.systemd}/bin/systemctl restart ${serviceUnit}"
      if failed
        port ${toString listenPort}
        protocol http request "/api/health" status 200
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert

    check program "gitea-mirror mirror-health" with path "${mirrorHealthCheckScript}"
      group container-services
      if status != 0 for 2 cycles then alert
  '';
}
