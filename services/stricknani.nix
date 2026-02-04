{
  config,
  inputs,
  pkgs,
  ...
}:
let
  user = "stricknani";
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
in
{
  imports = [
    inputs.stricknani.nixosModules.default
  ];

  sops = {
    secrets = {
      "stricknani/secrets/secretKey" = {
        inherit (config.custom) sopsFile;
      };
      "stricknani/secrets/csrfSecretKey" = {
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
      "stricknani/sentry/dsnBackend" = {
        inherit (config.custom) sopsFile;
      };
      "stricknani/sentry/dsnFrontend" = {
        inherit (config.custom) sopsFile;
      };
    };

    templates."${envFileName}" = {
      content = ''
        SECRET_KEY="${config.sops.placeholder."stricknani/secrets/secretKey"}"
        CSRF_SECRET_KEY="${config.sops.placeholder."stricknani/secrets/csrfSecretKey"}"
        INITIAL_ADMIN_EMAIL="${config.sops.placeholder."stricknani/initialAdmin/username"}"
        INITIAL_ADMIN_PASSWORD="${config.sops.placeholder."stricknani/initialAdmin/password"}"
        OPENAI_API_KEY="${config.sops.placeholder."stricknani/openaiApiKey"}"
        SENTRY_DSN_BACKEND="${config.sops.placeholder."stricknani/sentry/dsnBackend"}"
        SENTRY_DSN_FRONTEND="${config.sops.placeholder."stricknani/sentry/dsnFrontend"}"
      '';
      owner = user;
      group = user;
      mode = "0400";
    };
  };

  services.stricknani = {
    enable = true;
    package = stricknaniPkg;
    inherit dataDir;
    inherit port;
    bindHost = "127.0.0.1";
    hostName = mainHost;
    inherit serverAliases;
    secretKeyFile = config.sops.templates."${envFileName}".path;
    nginx.enable = true;
    extraConfig = {
      COOKIE_SAMESITE = "strict";
      FEATURE_SIGNUP_ENABLED = "false";
      FEATURE_WAYBACK_ENABLED = "true";
      FEATURE_AI_IMPORT_ENABLED = "false";
    };
  };

  services.nginx.virtualHosts."${mainHost}".acmeRoot = null;
}
