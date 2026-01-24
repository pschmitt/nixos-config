{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  domain = "anika.blue";
  mainHost = "wool.${domain}";
  serverAliases = [
    "stricken.${domain}"
    "wolle.${domain}"
  ];
  dataDir = "/var/lib/stricknani";
  port = 7674;
  envFileName = "stricknani.env";
  stricknaniPkg = inputs.stricknani.packages.${pkgs.stdenv.hostPlatform.system}.stricknani;

  user = "stricknani";
  group = user;
in
{
  sops = {
    secrets = {
      "stricknani/secretKey" = {
        inherit (config.custom) sopsFile;
      };
      "stricknani/initialAdmin/password" = {
        inherit (config.custom) sopsFile;
      };
      "stricknani/initialAdmin/username" = {
        inherit (config.custom) sopsFile;
      };
      "stricknani/openaiApiKey" = {
        inherit (config.custom) sopsFile;
      };
      "stricknani/sentryDsn" = {
        inherit (config.custom) sopsFile;
      };
    };

    templates."${envFileName}" = {
      content = ''
        SECRET_KEY="${config.sops.placeholder."stricknani/secretKey"}"
        INITIAL_ADMIN_EMAIL="${config.sops.placeholder."stricknani/initialAdmin/username"}"
        INITIAL_ADMIN_PASSWORD="${config.sops.placeholder."stricknani/initialAdmin/password"}"
        OPENAI_API_KEY="${config.sops.placeholder."stricknani/openaiApiKey"}"
        SENTRY_DSN="${config.sops.placeholder."stricknani/sentryDsn"}"
      '';
      owner = "stricknani";
      group = "stricknani";
      mode = "0400";
    };
  };

  users.users."${user}" = {
    isSystemUser = true;
    group = "stricknani";
    home = dataDir;
  };
  users.groups.stricknani = { };

  systemd.services.stricknani = {
    description = "Stricknani knitting project manager";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      BIND_HOST = "127.0.0.1";
      BIND_PORT = toString port;
      MEDIA_ROOT = "${dataDir}/media";
      DATABASE_URL = "sqlite:///${dataDir}/stricknani.db";
      ALLOWED_HOSTS = lib.concatStringsSep "," (
        [ mainHost ]
        ++ serverAliases
        ++ [
          "127.0.0.1"
          "localhost"
        ]
      );
      COOKIE_SAMESITE = "strict";
      FEATURE_SIGNUP_ENABLED = "false";
    };
    serviceConfig = {
      EnvironmentFile = config.sops.templates."${envFileName}".path;
      ExecStart = lib.getExe stricknaniPkg;
      User = user;
      Group = group;
      WorkingDirectory = dataDir;
      StateDirectory = "stricknani";
      StateDirectoryMode = "0750";
      Restart = "on-failure";
      RestartSec = 10;
      UMask = "0077";
    };
  };

  services.nginx.virtualHosts."${mainHost}" = {
    enableACME = true;
    acmeRoot = null;
    forceSSL = true;
    inherit serverAliases;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      recommendedProxySettings = true;
      proxyWebsockets = true;
    };
  };

  services.monit.config = lib.mkAfter ''
    check host "stricknani" with address "${mainHost}"
      group services
      restart program = "${pkgs.systemd}/bin/systemctl restart stricknani"
      if failed
        port 443
        protocol https
        request "/healthz"
        with timeout 15 seconds
      then restart
      if 5 restarts within 10 cycles then alert
  '';
}
