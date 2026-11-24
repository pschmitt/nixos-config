{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.teams-live;
  secrets = config.sops.secrets;

  # Readable by the service and restarting it when the value changes.
  serviceSecret =
    extra:
    {
      owner = cfg.user;
      inherit (cfg) group;
      mode = "0400";
      restartUnits = [ "teams-live.service" ];
    }
    // extra;
  hostSecret = config.sops.mkHostSecret (serviceSecret { });

  # A value teams-live reads from the secret file at startup (docs/nix.md).
  secretValue = name: { _secret = secrets.${name}.path; };

  defaultHost = "teams-live.${config.domains.main}";
  webhookHost = lib.head (cfg.webhookHostNames ++ [ defaultHost ]);
  webhookPort = 3005;
  backend = "http://127.0.0.1:${toString webhookPort}";
  approvalBackend = "http://127.0.0.1:${toString cfg.approval.port}";

  approveLocation = {
    proxyPass = approvalBackend;
    recommendedProxySettings = true;
    extraConfig = ''
      access_log off;
      error_log /dev/null crit;
      proxy_buffering off;
      proxy_cache off;
      client_max_body_size 4k;
    '';
  };
in
{
  sops.secrets = {
    "teams-live/credentials" = hostSecret;
    "teams-live/gitlab-token" = hostSecret;
    "teams-live/gitlab-personal-token" = hostSecret;
    "teams-live/personal-teams-mri" = hostSecret;
    "teams-live/personal-gitlab-username" = hostSecret;
    "teams-live/gitlab-url" = hostSecret;
    "teams-live/gitlab-group" = hostSecret;
    "teams-live/gitlab-webhook-secret" = hostSecret;
    "teams-live/conversation-notes" = hostSecret;
    "teams-live/conversation-team" = hostSecret;
    "teams-live/jira-url" = hostSecret;
    "teams-live/jira-token" = hostSecret;
    "teams-live/jira-board-id" = hostSecret;
    "teams-live/confluence-token" = hostSecret;
    "teams-live/troll-user" = hostSecret;
    "teams-live/tv-webhook" = hostSecret;
    "teams-live/tv-state-entity" = hostSecret;
    "teams-live/tv-mute-webhook" = hostSecret;
    "teams-live/tv-unmute-webhook" = hostSecret;
    "teams-live/tv-volume-up-webhook" = hostSecret;
    "teams-live/tv-volume-down-webhook" = hostSecret;
    "opsgenie/gksv3-on-call/api-key" = hostSecret;
    "opsgenie/gksv3-support-schedule/api-key" = hostSecret;
    "opsgenie/edge-stack/api-key" = hostSecret;
    "browser-daemon/cluster-secret" = serviceSecret { };
    "home-assistant/token" = serviceSecret { sopsFile = config.sops.defaultSopsFile; };
  };

  assertions = [
    {
      assertion = !cfg.approval.enable || cfg.webhookHostNames != [ ];
      message = "services.teams-live.approval needs services.teams-live.webhookHostNames: the approval page is served there, never behind Authelia on the default host.";
    }
  ];

  services = {
    teams-live = {
      enable = true;
      settings = {
        teams = {
          credentials_file = secrets."teams-live/credentials".path;
          troll_user = secretValue "teams-live/troll-user";
          edit_own_url_messages = true;
          rich_messages = true;
        };

        browser_daemon = {
          url = "https://browser.fnuc.nb.brkn.lol";
          profile = "ha-msteams";
          secret_file = secrets."browser-daemon/cluster-secret".path;
        };

        gitlab = {
          host = secretValue "teams-live/gitlab-url";
          group = secretValue "teams-live/gitlab-group";
          token_file = secrets."teams-live/gitlab-token".path;
          fallback_token_files = [ secrets."teams-live/gitlab-personal-token".path ];
          user_token_mappings = [
            {
              teams_mri = secretValue "teams-live/personal-teams-mri";
              gitlab_username = secretValue "teams-live/personal-gitlab-username";
              token_index = 1;
            }
          ];
          history_max_age_minutes = 15;
          webhook = {
            enable = true;
            port = webhookPort;
            url = "https://${webhookHost}/webhook/gitlab";
            secret_file = secrets."teams-live/gitlab-webhook-secret".path;
            auto_setup = true;
          }
          // lib.optionalAttrs (cfg.webhook.adoptHooks != [ ]) {
            adopt_hooks = cfg.webhook.adoptHooks;
          }
          // lib.optionalAttrs cfg.webhook.acceptSharedSecret {
            accept_shared_secret = true;
          };
        }
        // lib.optionalAttrs cfg.approval.enable {
          # The page and its token endpoints are served on the first webhook
          # host name, at /approve (see the nginx location below).
          approve = {
            enable = true;
            host = "127.0.0.1";
            inherit (cfg.approval) port;
            base_url = "https://${webhookHost}/approve";
            link_ttl_seconds = cfg.approval.linkTtlSeconds;
            # Where an approving address is (offline, nothing is sent anywhere): shown in the MR comment.
            geoip_database = "${pkgs.dbip-city-lite}/share/dbip/dbip-city-lite.mmdb";
            # "Sign in with GitLab" before a confirmation: the page learns who confirms.
            oauth = {
              auto_setup = true;
            };
          };
        };

        jira = {
          url = secretValue "teams-live/jira-url";
          token_file = secrets."teams-live/jira-token".path;
          board_id = secretValue "teams-live/jira-board-id";
        };

        confluence = {
          url = "https://wiki.wiit.one";
          token_file = secrets."teams-live/confluence-token".path;
        };

        # Profile pictures on cards where Teams has none: Jira and Confluence are asked by
        # default. Our own GitLab service account (the one that approves merge requests) is in
        # no directory, so it gets the Teams logo, under its display name and, should GitLab
        # show that instead, its username.
        avatars.overrides =
          map
            (name: {
              inherit name;
              file = ./teams-live/ms-teams-bot.png;
            })
            [
              "MS Teams bot"
              "sa_teams_live"
            ];

        opsgenie = {
          on_call_key = secretValue "opsgenie/gksv3-on-call/api-key";
          support_key = secretValue "opsgenie/gksv3-support-schedule/api-key";
          edge_key = secretValue "opsgenie/edge-stack/api-key";
        };

        home_assistant = {
          # Straight over NetBird: the public vhost times out slow service calls
          # (HR WORKS) after 60s and retries them through Nabu Casa.
          url = "http://ha.${config.domains.netbird}:8123";
          token_file = secrets."home-assistant/token".path;
        };

        # /tv controls. One Home Assistant webhook switches the OBS scene; the
        # same scene entity is the readback, so /tv next|prev never relies on
        # process memory. /tv mute, /tv unmute and /tv vol up|down each have
        # their own fixed-meaning webhook, which acts on the active TV OBS
        # source only (/tv vol up also unmutes it).
        tv.switch = {
          webhooks =
            lib.genAttrs [ "ard" "zdf" "tagesschau" "off" ] (_: secretValue "teams-live/tv-webhook")
            // {
              mute = secretValue "teams-live/tv-mute-webhook";
              unmute = secretValue "teams-live/tv-unmute-webhook";
              volume_up = secretValue "teams-live/tv-volume-up-webhook";
              volume_down = secretValue "teams-live/tv-volume-down-webhook";
            };
          state = {
            entity_id = secretValue "teams-live/tv-state-entity";
            map.off = [ "🚬 brb" ];
          };
        };

        conversations = [
          {
            id = secretValue "teams-live/conversation-notes";
            name = "Notes (Self)";
            gitlab = true;
          }
          {
            id = secretValue "teams-live/conversation-team";
            name = "Team";
            gitlab = true;
          }
        ];
      };
    };

    nginx.virtualHosts = {
      ${defaultHost} = {
        enableACME = true;
        forceSSL = true;
        authelia.enable = true;

        locations = {
          "^~ /webhook/" = {
            proxyPass = backend;
            recommendedProxySettings = true;
            authelia = false;
          };
          "= /healthz" = {
            proxyPass = backend;
            recommendedProxySettings = true;
            authelia = false;
          };
          "/" = {
            proxyPass = backend;
            recommendedProxySettings = true;
          };
        };
      };
    }
    # Webhook and health check only, no Authelia: GitLab authenticates with
    # the shared secret and no other path is proxied.
    // lib.genAttrs cfg.webhookHostNames (_: {
      enableACME = true;
      forceSSL = true;
      locations = {
        # Everything else is not served (nginx would show its welcome page).
        "/".return = "404";
        "^~ /webhook/" = {
          proxyPass = backend;
          recommendedProxySettings = true;
        };
        "= /healthz" = {
          proxyPass = backend;
          recommendedProxySettings = true;
        };
      }
      // lib.optionalAttrs cfg.approval.enable {
        # The link token is the only credential: keep it out of nginx logs,
        # including the request line that error messages quote. The service
        # sets its own cache and CSP headers and checks Origin itself, so
        # nothing is rewritten, buffered or cached here. `= /approve` is
        # proxied too (no 301), the page then reads the fragment itself.
        "= /approve" = approveLocation;
        "^~ /approve/" = approveLocation;
      };
    });

    monit.checks.teams-live = {
      type = "program";
      path = cfg.healthCheck;
      group = [
        "services"
        "teams"
      ];
      restartUnit = "teams-live.service";
      conditions = ''
        if status > 0 for 2 cycles then restart
        if 3 restarts within 10 cycles then alert
      '';
    };
  };
}
