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
