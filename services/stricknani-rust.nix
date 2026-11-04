# Stricknani on the Rust server + new web UI, via the upstream NixOS module
# (nix/module.nix of the `stricknani` flake input, backend = "rust").
#
# Selected by `stage = "rust"` / "rust-maintenance" in ./stricknani.nix.
#
# - Fresh data dir /var/lib/stricknani-rust (populated by
#   `stricknani-server import-snapshot` from a frozen snapshot of the Python
#   data during the cutover window). The Python data in /var/lib/stricknani is
#   hidden from the service and left untouched for rollback.
# - No SOPS env file: secrets (the Authelia OIDC client secret and the Sentry
#   DSN) are passed as file paths.
# - Link imports and AI (via Hermes) are on; OCR and Wayback stay disabled.
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
  dataDir = "/var/lib/stricknani-rust";
  port = 7674;
  package = inputs.stricknani.packages.${pkgs.stdenv.hostPlatform.system}.stricknani;
in
{
  imports = [
    inputs.stricknani.nixosModules.default
  ];

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
    inherit package dataDir port;
    # The importer publishes database.sqlite3 + media/ (not the module's
    # default rust.sqlite3).
    databaseUrl = "sqlite:${dataDir}/database.sqlite3";
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
      RUST_SIGNUP_ENABLED = "false";
      RUST_OCR_ENABLED = "false";
      RUST_WAYBACK_ENABLED = "false";
    };
  };

  # Same system user as the Python service, but keep the Rust process away from
  # the Python data (rollback copy).
  systemd.services.stricknani.serviceConfig.InaccessiblePaths = [ "/var/lib/stricknani" ];
}
