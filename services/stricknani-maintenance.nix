# Edge maintenance mode for Stricknani.
#
# When enabled, every request to the Stricknani vhost (all aliases) is answered
# by nginx with a friendly 503 page plus `Retry-After`; /api/ gets a JSON body.
# This is the write barrier required by the cutover runbook. Only the ACME
# HTTP-01 challenge path is let through so certificate renewals keep working.
# Works with both backends: it only needs services.stricknani.hostName.
{
  config,
  lib,
  ...
}:
let
  cfg = config.stricknani.maintenance;
  vhost = config.services.stricknani.hostName;
  # Served inline with `return`, so every method gets the 503 (a static file
  # would answer 405 to POST). Must not contain single quotes or $.
  html = ''
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="refresh" content="60">
      <meta name="robots" content="noindex">
      <title>Stricknani - Wartung / Maintenance</title>
      <style>
        :root { color-scheme: light dark; --bg: #faf7f2; --fg: #2b2622; --muted: #6f655c; --accent: #9a4d3f; }
        @media (prefers-color-scheme: dark) { :root { --bg: #1d1a18; --fg: #efe9e2; --muted: #a39a91; --accent: #e08a78; } }
        body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg); color: var(--fg);
               font: 17px/1.55 system-ui, -apple-system, "Segoe UI", sans-serif; }
        main { max-width: 34rem; padding: 2rem 1.5rem; }
        h1 { font-size: 1.6rem; margin: 0 0 .5rem; color: var(--accent); }
        p { margin: .4rem 0; }
        .muted { color: var(--muted); font-size: .95rem; }
        hr { border: 0; border-top: 1px solid var(--muted); opacity: .3; margin: 1.5rem 0; }
      </style>
    </head>
    <body>
      <main>
        <h1>Stricknani macht eine kurze Pause</h1>
        <p>Wir ziehen gerade auf eine neue Version um. Deine Projekte und Garne sind sicher.
           Bitte versuche es in ein paar Minuten noch einmal. Diese Seite aktualisiert sich selbst.</p>
        <p class="muted">Die App synchronisiert danach automatisch weiter.</p>
        <hr>
        <h1>Stricknani is taking a short break</h1>
        <p>We are moving to a new version. Your projects and yarns are safe.
           Please try again in a few minutes. This page refreshes itself.</p>
        <p class="muted">The app will resume syncing automatically afterwards.</p>
      </main>
    </body>
    </html>
  '';
  json = ''{"error":{"code":"maintenance","message":"Stricknani is under maintenance, retry later"}}'';
in
{
  options.stricknani.maintenance = {
    enable = lib.mkEnableOption "the Stricknani maintenance page (503 on every request)";

    retryAfter = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
      description = "Value of the Retry-After header, in seconds.";
    };

    bypassAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "192.0.2.10" ];
      description = ''
        Client addresses or CIDRs that still reach the backend during
        maintenance (for operator verification before lifting the barrier).
        Empty by default: nobody bypasses.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = vhost != null;
        message = "stricknani.maintenance needs services.stricknani.hostName.";
      }
    ];

    services.nginx = {
      commonHttpConfig = ''
        geo $stricknani_maint_client {
          default 1;
          ${lib.concatMapStringsSep "\n  " (a: "${a} 0;") cfg.bypassAddresses}
        }
        map $uri $stricknani_maint_path {
          ~^/\.well-known/acme-challenge/ 0;
          default 1;
        }
        map "$stricknani_maint_client$stricknani_maint_path" $stricknani_maint {
          "11" 1;
          default 0;
        }
        map "$stricknani_maint:$uri" $stricknani_maint_api {
          ~^1:/api/ 1;
          default 0;
        }
      '';

      virtualHosts.${vhost} = {
        extraConfig = ''
          if ($stricknani_maint_api) {
            rewrite ^ /__stricknani_maintenance_api last;
          }
          if ($stricknani_maint) {
            rewrite ^ /__stricknani_maintenance last;
          }
        '';
        locations."= /__stricknani_maintenance" = {
          extraConfig = ''
            internal;
            default_type text/html;
            add_header Retry-After "${toString cfg.retryAfter}" always;
            add_header Cache-Control "no-store" always;
            return 503 '${html}';
          '';
        };
        locations."= /__stricknani_maintenance_api" = {
          extraConfig = ''
            internal;
            default_type application/json;
            add_header Retry-After "${toString cfg.retryAfter}" always;
            add_header Cache-Control "no-store" always;
            return 503 '${json}';
          '';
        };
      };
    };
  };
}
