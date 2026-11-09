# Stricknani production (wool/stricken/wolle on rofl-10): the Rust server and
# web UI via the upstream NixOS module (nix/module.nix of the `stricknani`
# flake input). Data lives in /var/lib/stricknani (stricknani.sqlite3 +
# media/), the module's defaults.
#
# - No SOPS env file: secrets (the Authelia OIDC client secret and the Sentry
#   DSN) are passed as file paths.
# - Link imports, AI (via Hermes) and Wayback snapshots of pattern links are on;
#   OCR stays disabled.
# - stricknani.maintenance.enable = true answers every request with a 503
#   maintenance page (./stricknani-maintenance.nix), e.g. for a data restore.
{
  config,
  inputs,
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
  # Callback host must be listed in TRUSTED_HOSTS (hostName + serverAliases).
  oidcHost = "wolle.${domain}";
  port = 7674;
  package = inputs.stricknani.packages.${pkgs.stdenv.hostPlatform.system}.stricknani;
in
{
  imports = [
    inputs.stricknani.nixosModules.default
    ./stricknani-maintenance.nix
  ];

  stricknani.maintenance.enable = false;

  # The server binary (account CLI, snapshot importer) for operators.
  environment.systemPackages = [ package ];

  sops.secrets = {
    "stricknani/oidc/clientSecret" = config.sops.mkHostSecret {
      owner = "stricknani";
      group = "stricknani";
    };
    # Same value as Hermes's API server key (services/hermes.nix).
    "stricknani/hermesApiKey" = config.sops.mkHostSecret {
      key = "hermes/apiServer/key";
      owner = "stricknani";
      group = "stricknani";
    };
    # One Sentry project (stricknani) for server, web and Android; the apps report
    # through the server's tunnel, and users can opt out in their account settings.
    "stricknani/sentry/dsnBackend" = config.sops.mkHostSecret {
      owner = "stricknani";
      group = "stricknani";
    };
  };

  services.stricknani = {
    enable = true;
    backend = "rust";
    inherit package port;
    bindHost = "127.0.0.1";
    hostName = mainHost;
    inherit serverAliases;
    nginx.enable = true;
    sentry.dsnFile = config.sops.secrets."stricknani/sentry/dsnBackend".path;
    # Link imports for projects and yarns; the AI fills gaps through Hermes's
    # loopback OpenAI-compatible API server (tool-less for that platform).
    imports.enable = true;
    ai = {
      enable = true;
      provider = "custom";
      baseUrl = "http://127.0.0.1:8642/v1";
      model = "hermes-agent";
      apiKeyFile = config.sops.secrets."stricknani/hermesApiKey".path;
      timeoutSeconds = 90;
      # Let Hermes open the pattern page in its browser-daemon browser.
      browse = true;
      browseTimeoutSeconds = 180;
    };

    oidc = {
      enable = true;
      issuer = "https://auth.${config.domains.main}";
      clientId = "stricknani";
      clientSecretFile = config.sops.secrets."stricknani/oidc/clientSecret".path;
      callbackUri = "https://${oidcHost}/api/v2/auth/oidc/callback/authelia";
      nativeRedirectUris = [ "stricknani://oidc-callback" ];
    };

    extraConfig = {
      SIGNUP_ENABLED = "false";
      OCR_ENABLED = "false";
      WAYBACK_ENABLED = "true";
    };
  };
}
