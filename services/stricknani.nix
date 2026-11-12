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

  # Browsers land on wolle only: passkeys are bound to it (passkeys.rpId below). The web UI on
  # the wool/stricken aliases redirects there; the API, media and /.well-known stay reachable on
  # every alias so Android apps configured with an alias keep working (OkHttp drops the
  # Authorization header on a cross-host redirect).
  services.nginx.virtualHosts.${mainHost}.locations =
    let
      uiLocation = {
        proxyPass = "http://127.0.0.1:${toString port}";
        recommendedProxySettings = true;
        extraConfig = ''
          if ($host != "${oidcHost}") {
            return 308 https://${oidcHost}$request_uri;
          }
        '';
      };
    in
    {
      "= /" = uiLocation;
      "/app/" = uiLocation;
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

    # Android App Links: the persistent CI signing key of every APK (release and debug), so
    # a project or yarn link opens the app directly.
    # Passkeys are bound to this host (WebAuthn RP ID). Not the parent domain: Android's
    # Credential Manager checks assetlinks.json on the RP ID itself. Passkeys therefore work on
    # wolle only, not on the wool/stricken aliases.
    passkeys.rpId = oidcHost;

    android.appLinkFingerprints = [
      "61:50:52:4C:34:01:C2:32:A8:B5:82:E8:73:D6:92:E7:1A:D9:C6:72:63:17:FC:6C:69:88:90:40:F6:0D:A1:1F"
    ];

    extraConfig = {
      SIGNUP_ENABLED = "false";
      OCR_ENABLED = "false";
      WAYBACK_ENABLED = "true";
    };
  };
}
