{
  config,
  lib,
  ...
}:
let
  dataDir = "/srv/gitea-mirror";
  listenPort = 54439;
  containerUid = 1000;
  containerGid = 1000;
  inherit (config.networking) hostName;
  netbirdHost = "${hostName}.${config.domains.netbird}";
  tailscaleHost = "${hostName}.${config.domains.tailscale}";
  vpnHost = "${hostName}.${config.domains.vpn}";
  primaryOrigin = "http://${netbirdHost}:${toString listenPort}";
  trustedOrigins = lib.strings.concatStringsSep "," [
    primaryOrigin
    "http://${tailscaleHost}:${toString listenPort}"
    "http://${vpnHost}:${toString listenPort}"
  ];
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

  virtualisation.oci-containers.containers.gitea-mirror = {
    autoStart = true;
    image = "ghcr.io/raylabshq/gitea-mirror:latest";
    pull = "always";
    user = "${toString containerUid}:${toString containerGid}";
    ports = [
      "0.0.0.0:${toString listenPort}:${toString listenPort}"
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
}
