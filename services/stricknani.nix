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
  aiUserEmail = "ai@${domain}";
  ensureAiUserScript = pkgs.writeShellScript "stricknani-ensure-ai-user" ''
    set -euo pipefail
    cd "${dataDir}"
    export DATABASE_URL="${config.services.stricknani.databaseUrl}"
    "${stricknaniPkg}/bin/stricknani-cli" user create \
      --email "${aiUserEmail}" \
      --password "$(cat "${config.sops.secrets."stricknani/aiUser/password".path}")" \
      --no-admin
  '';
in
{
  imports = [
    inputs.stricknani.nixosModules.default
  ];

  sops = {
    secrets = {
      "stricknani/secrets/secretKey" = config.custom.mkSecret {
      };
      "stricknani/secrets/csrfSecretKey" = config.custom.mkSecret {
      };
      "stricknani/initialAdmin/password" = config.custom.mkSecret {
      };
      "stricknani/initialAdmin/username" = config.custom.mkSecret {
      };
      "stricknani/openaiApiKey" = config.custom.mkSecret {
      };
      "stricknani/sentry/dsnBackend" = config.custom.mkSecret {
      };
      "stricknani/sentry/dsnFrontend" = config.custom.mkSecret {
      };
      "stricknani/aiUser/password" = config.custom.mkSecret {
        owner = user;
        group = user;
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
      FEATURE_AI_IMPORT_ENABLED = "true";
    };
  };

  services.nginx.virtualHosts."${mainHost}".acmeRoot = null;

  # Dedicated non-admin account for AI-assisted testing (Android app end-to-end
  # verification etc.) so an agent never touches the real users' project/yarn
  # data. `stricknani-cli user create` upserts (creates or resets the
  # password), so this is idempotent and safe to run on every activation.
  systemd.services.stricknani-ensure-ai-user = {
    description = "Ensure the dedicated Stricknani AI-testing user exists";
    after = [ "stricknani.service" ];
    wants = [ "stricknani.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = user;
      Group = user;
      ExecStart = ensureAiUserScript;
    };
  };
}
