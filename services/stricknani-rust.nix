# Stricknani on the Rust server + new web UI, via the upstream NixOS module
# (nix/module.nix of the `stricknani` flake input, backend = "rust").
#
# Selected by `stage = "rust"` / "rust-maintenance" in ./stricknani.nix.
#
# - Fresh data dir /var/lib/stricknani-rust (populated by
#   `stricknani-server import-snapshot` from a frozen snapshot of the Python
#   data during the cutover window). The Python data in /var/lib/stricknani is
#   hidden from the service and left untouched for rollback.
# - No SOPS env file: the Rust server has no SECRET_KEY/CSRF/initial-admin/
#   Sentry settings. The only secret is the Authelia OIDC client secret, passed
#   as a file path.
# - AI, OCR, external imports and Wayback stay disabled until reviewed
#   separately (cutover runbook).
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

  sops.secrets."stricknani/oidc/clientSecret" = config.sops.mkHostSecret {
    owner = "stricknani";
    group = "stricknani";
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
      RUST_AI_ENABLED = "false";
      RUST_OCR_ENABLED = "false";
      RUST_EXTERNAL_IMPORTS_ENABLED = "false";
      RUST_WAYBACK_ENABLED = "false";
    };
  };

  # Same system user as the Python service, but keep the Rust process away from
  # the Python data (rollback copy).
  systemd.services.stricknani.serviceConfig.InaccessiblePaths = [ "/var/lib/stricknani" ];
}
