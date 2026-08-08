{
  config,
  lib,
  pkgs,
  ...
}:
let
  healthchecksUser = config.mainUser.username;
  healthchecksGroup = config.users.users.${healthchecksUser}.group;
  dataDir = "/mnt/data/srv/healthchecks/config";
  healthchecksHost = "hc.${config.domains.main}";
  healthchecksAliases = [ "healthchecks.${config.domains.main}" ];
  healthchecksEmail = "healthchecks@${config.domains.main}";
  healthchecksPort = 8000;
  csrfTrustedOrigins = map (host: "https://${host}") ([ healthchecksHost ] ++ healthchecksAliases);

  localSettings = pkgs.writeText "healthchecks-local-settings.py" ''
    from pathlib import Path

    CSRF_TRUSTED_ORIGINS = ${builtins.toJSON csrfTrustedOrigins}
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
    STATICFILES_DIRS = [
        Path(__file__).resolve().parent.parent / "static",
        Path("${dataDir}/img"),
    ]
  '';

  healthchecksPackage = pkgs.healthchecks.overrideAttrs (_old: {
    version = "4.3";
    src = pkgs.fetchFromGitHub {
      owner = "healthchecks";
      repo = "healthchecks";
      tag = "v4.3";
      hash = "sha256-8S7hIUFSr88jNEwGM4mSQAv+EdH/ynT9MvATabmtp5s=";
    };
    postInstall = ''
      cat ${localSettings} >> $out/opt/healthchecks/hc/local_settings.py
    '';
  });

  secretAttrs = {
    owner = healthchecksUser;
    group = healthchecksGroup;
    mode = "0400";
  };
in
{
  sops.secrets = {
    "healthchecks/secret-key" = config.custom.mkSecret secretAttrs;
    "healthchecks/email-host-password" = config.custom.mkSecret secretAttrs;
    "healthchecks/discord-client-secret" = config.custom.mkSecret secretAttrs;
  };

  services = {
    healthchecks = {
      enable = true;
      package = healthchecksPackage;
      user = healthchecksUser;
      group = healthchecksGroup;
      listenAddress = "127.0.0.1";
      port = healthchecksPort;
      inherit dataDir;

      settings = {
        ALLOWED_HOSTS = [ healthchecksHost ] ++ healthchecksAliases;
        DB = "sqlite";
        DB_NAME = "${dataDir}/hc.sqlite";
        DEBUG = false;
        DEFAULT_FROM_EMAIL = healthchecksEmail;
        DISCORD_CLIENT_ID = "838180668135571466"; # gitleaks:allow - public Discord client ID
        DISCORD_CLIENT_SECRET_FILE = config.sops.secrets."healthchecks/discord-client-secret".path;
        EMAIL_HOST = "127.0.0.1";
        EMAIL_HOST_PASSWORD_FILE = config.sops.secrets."healthchecks/email-host-password".path;
        EMAIL_HOST_USER = healthchecksEmail;
        EMAIL_PORT = "587";
        EMAIL_USE_TLS = "True";
        REGISTRATION_OPEN = false;
        SECRET_KEY_FILE = config.sops.secrets."healthchecks/secret-key".path;
        SITE_NAME = healthchecksHost;
        SITE_ROOT = "https://${healthchecksHost}";
      };
    };

    nginx.virtualHosts.${healthchecksHost} = {
      serverAliases = healthchecksAliases;
      listen = [
        {
          addr = "0.0.0.0";
          port = 2020;
        }
      ];
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString healthchecksPort}";
        recommendedProxySettings = false;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;
        '';
      };
    };

    monit.config = lib.mkAfter ''
      check host "healthchecks" with address "127.0.0.1"
        group services
        if failed
          port ${toString healthchecksPort}
          protocol http
          with hostheader "${healthchecksHost}"
          request "/"
          with timeout 10 seconds
        for 3 cycles
        then alert
    '';
  };

  systemd.services =
    lib.genAttrs
      [
        "healthchecks"
        "healthchecks-sendalerts"
        "healthchecks-sendreports"
      ]
      (_: {
        after = [ "mnt-data.mount" ];
        requires = [ "mnt-data.mount" ];
        unitConfig.RequiresMountsFor = [ dataDir ];
      });
}
