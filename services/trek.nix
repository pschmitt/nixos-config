{
  config,
  ...
}:
let
  trekHost = "trek.${config.domains.main}";
  listenPort = 32037;
  containerPort = 3000;
  dataDir = "/mnt/data/srv/trek";
  containerBackend = config.virtualisation.oci-containers.backend;
  # renovate: datasource=docker depName=mauriceboe/trek
  trekVersion = "4.3.1";
in
{
  sops = {
    secrets."trek/encryption-key" = config.sops.mkHostSecret {
      mode = "0400";
      restartUnits = [ "${containerBackend}-trek.service" ];
    };

    secrets."trek/smtp-password" = config.sops.mkHostSecret {
      mode = "0400";
      restartUnits = [ "${containerBackend}-trek.service" ];
    };

    templates."trek/env" = {
      content = ''
        ENCRYPTION_KEY=${config.sops.placeholder."trek/encryption-key"}
        ALLOWED_ORIGINS=https://${trekHost}
        APP_URL=https://${trekHost}
        TRUST_PROXY=1
        TZ=${config.time.timeZone}
        SMTP_HOST=mail.${config.domains.main}
        SMTP_PORT=465
        SMTP_USER=trek@${config.domains.main}
        SMTP_PASS=${config.sops.placeholder."trek/smtp-password"}
        SMTP_FROM=TREK <trek@${config.domains.main}>
      '';
      mode = "0400";
      restartUnits = [ "${containerBackend}-trek.service" ];
    };
  };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 root root - -"
    "d ${dataDir}/data 0750 root root - -"
    "d ${dataDir}/uploads 0750 root root - -"
  ];

  virtualisation.oci-containers.containers.trek = {
    image = "mauriceboe/trek:${trekVersion}";
    pull = "always";
    autoStart = true;
    serviceConfig.restartIfChanged = true;
    environment = {
      NODE_ENV = "production";
      PORT = toString containerPort;
      LOG_LEVEL = "info";
    };
    environmentFiles = [ config.sops.templates."trek/env".path ];
    volumes = [
      "${dataDir}/data:/app/data"
      "${dataDir}/uploads:/app/uploads"
    ];
    ports = [ "127.0.0.1:${toString listenPort}:${toString containerPort}" ];
    extraOptions = [
      "--read-only"
      "--security-opt=no-new-privileges:true"
      "--cap-drop=ALL"
      "--cap-add=CHOWN"
      "--cap-add=SETUID"
      "--cap-add=SETGID"
      "--tmpfs=/tmp:noexec,nosuid,size=128m"
    ];
  };
}
