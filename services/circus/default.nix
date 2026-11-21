# Circus CI (github:manic-systems/circus): server, evaluator, queue-runner and
# PostgreSQL on one host, which must share one Nix store (see README.md). The
# queue-runner never builds here: all builds go to circus-agent instances
# (./agent.nix). Statuses, PR webhooks, S3 upload and GitHub Actions agents are
# opt-in.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.circus;
  inherit (config.networking) hostName;

  # Public dashboard behind Authelia, and a NetBird-only name that agents
  # (rofl-16, GitHub runners joined to NetBird) use for the binary cache.
  publicHost = "circus.${config.domains.main}";
  buildHost = "build.${config.domains.main}";
  tailnetHost = "circus.${hostName}.${config.domains.netbird}";

  serverPort = 3000;
  rpcPort = 8443;
  tailnetCertDir = config.security.acme.certs.${tailnetHost}.directory;
  runnerUrl = "circus+tls://${tailnetHost}:${toString rpcPort}";

  secret = name: config.sops.secrets."circus/${name}".path;
  placeholder = name: config.sops.placeholder."circus/${name}";

  # NetBird and Tailscale (trusted interfaces on the build nodes): the
  # tailnet vhost only answers clients from these ranges.
  tailnetRanges = [
    "100.64.0.0/10"
    "fd7a:115c:a1e0::/48"
    "fd8d:fa54:9081::/48"
  ];

  dashboardLocation = tailnetOnly: methods: uri: {
    proxyPass = "http://127.0.0.1:${toString serverPort}${uri}";
    proxyWebsockets = true;
    recommendedProxySettings = false;
    extraConfig = ''
      proxy_set_header Host ${buildHost};
      proxy_set_header X-Forwarded-Host ${buildHost};
      proxy_set_header X-Forwarded-Proto https;
    ''
    + lib.optionalString tailnetOnly ''
      ${lib.concatMapStrings (range: "allow ${range};\n") tailnetRanges}
      deny all;
    ''
    + ''
      limit_except ${methods} { deny all; }
    '';
  };

  dashboardLocations =
    tailnetOnly:
    let
      get = dashboardLocation tailnetOnly "GET";
      stream = get "";
    in
    {
      "/".return = "404";
      "= /dash" = get "/dash";
      "~ \"^/dash/project/[0-9a-f-]{36}$\"" = get "";
      "= /simple".return = "302 /dash$is_args$args";
      "~ \"^/simple/project/(?<legacy_project_id>[0-9a-f-]{36})$\"".return =
        "302 /dash/project/$legacy_project_id$is_args$args";
      "= /login" = dashboardLocation tailnetOnly "GET POST" "/login";
      "^~ /_topcoat/" = get "";
      "^~ /static/" = get "";
      "~ \"^/build/[0-9a-f-]{36}/log$\"" = get "";
      "~ \"^/api/v1/builds/[0-9a-f-]{36}/log/stream$\"" = stream // {
        extraConfig = stream.extraConfig + "proxy_buffering off;\n";
      };
    };

  # The infrastructure project, which has its own jobset and build policy.
  repositoryUrl = "https://github.com/pschmitt/nixos-config";

  # GitHub App installation token, refreshed by circus-github-token below.
  # Circus reads it on every status (pschmitt/circus), so it is passed as a
  # path the services read live, not as a *_file setting, which the upstream
  # module would turn into a systemd credential copied once at start.
  githubTokenDir = "/run/circus-github-token";
  qemuOverflowStatusPath = "/var/lib/circus/qemu-overflow.json";
  githubTokenFile = "${githubTokenDir}/token";
  githubTokenGroup = "circus-github-token";
  githubTokenMinter = pkgs.writeShellApplication {
    name = "circus-github-token";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.openssl
    ];
    text = builtins.readFile ./scripts/circus-github-token.sh;
  };
  # Units that send notifications: they get the token's group and its path.
  notifyingUnits = [
    "circus-evaluator"
    "circus-queue-runner"
  ];

  # The host's nix.conf snippet with the git.wiit.one token (private config,
  # root-only like nixbot's): the evaluator fetches GitLab flake inputs with
  # it. Agents only realise derivations through the root nix-daemon, which
  # already includes it.
  gitlabNixConf = config.sops.templates.nix-access-token-gitlab.path or null;

  s3KeyIdEnv = lib.optionalString cfg.s3Upload.enable ''
    CIRCUS_CACHE_UPLOAD__S3__ACCESS_KEY_ID=${placeholder "s3/access-key-id"}
  '';
in
{
  imports = [
    inputs.circus.nixosModules.circus
    ./agent.nix
    ./effects
  ];

  options.services.circus = {
    rworkerPool.enable = lib.mkEnableOption ''
      ephemeral pool agents on rworkers (the rworker autoscaler on the ad-hoc
      control host, profile circus): a second agent join token
      (circus/pool-join-token-sha256) and a read-only API key
      (circus/autoscaler-api-key) for its demand checks, which read the
      operator queue on the tailnet-only vhost
    '';

    qemuOverflow.enable = lib.mkEnableOption ''
      the one-worker ARM overflow fallback after the QEMU image is available
      in the worker pool
    '';

    allowLocalBuilds = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow the queue-runner to build on this host. Off: every build goes to
        an agent, enforced by an assertion.
      '';
    };

    githubStatuses.enable = lib.mkEnableOption ''
      commit statuses (context circus/<job>) on GitHub, using the GitHub App
      token (githubApp) or else the token in the host secret
      circus/github-status-token
    '';

    githubApp = {
      enable = lib.mkEnableOption ''
        authenticating to GitHub as a GitHub App: a timer mints installation
        tokens from the host secrets circus/github-app/app-id and
        circus/github-app/private-key
      '';
      repository = lib.mkOption {
        type = lib.types.str;
        default = lib.removePrefix "https://github.com/" repositoryUrl;
        description = "owner/repo whose App installation the tokens are minted for.";
      };
    };

    githubWebhook.enable = lib.mkEnableOption ''
      the GitHub webhook endpoint (pull-request evaluations), signed with the
      host secret circus/github-webhook-secret
    '';

    s3Upload.enable = lib.mkEnableOption ''
      presigned S3 upload of build outputs (bucket from the private
      tofu/circus-cache.tf, keys in the host secrets circus/s3/*)
    '';

    githubActionsAgents = {
      enable = lib.mkEnableOption ''
        ephemeral aarch64 circus-agents on GitHub Actions arm runners
        (.github/workflows/circus-builder.yml), joining over NetBird
      '';
      agentBinaryUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "URL of a static aarch64 circus-agent matching this queue-runner.";
      };
      agentBinarySha256 = lib.mkOption {
        type = lib.types.strMatching "[0-9a-f]{64}";
        description = ''
          SHA-256 (hex) of the agent binary. It travels as the URL fragment
          (`#sha256=...`), which curl ignores and circus-builder.yml checks
          before running the binary.
        '';
      };
    };
  };

  config = {
    # The queue-runner writes the short-lived report in its StateDirectory.
    users.users.circus-server.extraGroups = lib.mkIf cfg.qemuOverflow.enable [ "circus" ];

    assertions = [
      {
        assertion =
          cfg.allowLocalBuilds
          || (cfg.settings.queue_runner.workers == 0 && cfg.settings.queue_runner.local_systems == [ ]);
        message = "services.circus: the queue-runner must not build locally (workers = 0, local_systems = []).";
      }
      {
        assertion = !cfg.githubActionsAgents.enable || cfg.githubActionsAgents.agentBinaryUrl != "";
        message = "services.circus.githubActionsAgents.agentBinaryUrl must be set.";
      }
    ];

    sops = {
      secrets = {
        # API key of the declarative admin (dashboard login and circusctl).
        "circus/admin-api-key" = config.sops.mkHostSecret { };
        # Password of the declarative dashboard user pschmitt.
        "circus/users/pschmitt-password" = config.sops.mkHostSecret { };
        # Nix cache signing key (`nix key generate-secret`); public half below.
        "circus/cache-signing-key" = config.sops.mkHostSecret { };
        "circus/webhook-encryption-key" = config.sops.mkHostSecret { };
        # SHA-256 of circus/agent-join-token (./agent.nix).
        "circus/agent-join-token-sha256" = config.sops.mkHostSecret { };
      }
      // lib.optionalAttrs cfg.rworkerPool.enable {
        # SHA-256 of the pool's join token (held by the autoscaler, handed to
        # each pool worker in its user-data) and the autoscaler's API key.
        "circus/pool-join-token-sha256" = config.sops.mkHostSecret { };
        "circus/autoscaler-api-key" = config.sops.mkHostSecret { };
      }
      // lib.optionalAttrs cfg.githubWebhook.enable {
        "circus/github-webhook-secret" = config.sops.mkHostSecret { };
      }
      // lib.optionalAttrs (cfg.githubStatuses.enable && !cfg.githubApp.enable) {
        # Fine-grained token: commit statuses read/write on pschmitt/nixos-config.
        "circus/github-status-token" = config.sops.mkHostSecret { };
      }
      // lib.optionalAttrs cfg.githubApp.enable {
        # App id and private key (PEM) of the GitHub App circus-pschmitt.
        "circus/github-app/app-id" = config.sops.mkHostSecret { };
        "circus/github-app/private-key" = config.sops.mkHostSecret { };
      }
      // lib.optionalAttrs cfg.s3Upload.enable {
        "circus/s3/access-key-id" = config.sops.mkHostSecret { };
        "circus/s3/secret-access-key" = config.sops.mkHostSecret { };
      }
      // lib.optionalAttrs (cfg.githubActionsAgents.enable && !cfg.githubApp.enable) {
        # Fine-grained token: actions read/write on pschmitt/nixos-config.
        "circus/github-dispatch-token" = config.sops.mkHostSecret { };
      };

      # Values without a *_file setting reach Circus as CIRCUS_A__B
      # environment overrides, so they never land in the Nix store. Only the
      # queue-runner reads [queue_runner]: the server would reject a partial
      # rpc table.
      templates = {
        "circus-queue-runner.env".content = ''
          CIRCUS_QUEUE_RUNNER__RPC__JOIN_TOKENS="[{ name = 'rofl', token_hash = '${placeholder "agent-join-token-sha256"}' }${lib.optionalString cfg.rworkerPool.enable ", { name = 'rworker-pool', token_hash = '${placeholder "pool-join-token-sha256"}' }"}]"
        ''
        + s3KeyIdEnv;
        # The server presigns S3 GETs for cache downloads.
        "circus-server.env".content = s3KeyIdEnv;
        "circus-evaluator.env".content = lib.optionalString cfg.s3Upload.enable ''
          CIRCUS_EVALUATOR__S3_SUBSTITUTERS__ACCESS_KEY_ID=${placeholder "s3/access-key-id"}
        '';
      };
    };

    services = {
      circus = {
        enable = true;
        server.enable = true;
        evaluator.enable = true;
        queueRunner.enable = true;
        # Native PostgreSQL on this host, peer authentication (upstream module).
        database.createLocally = true;
        # Rotating App installation token (circus-github-token): read in place,
        # not copied into a credential at service start.
        runtimeFiles =
          lib.optional cfg.githubApp.enable githubTokenFile
          ++ lib.optional cfg.qemuOverflow.enable qemuOverflowStatusPath;

        settings = {
          server = {
            host = "127.0.0.1";
            port = serverPort;
            # nginx terminates TLS (publicHost).
            force_secure_cookies = true;
            allowed_origins = [
              "https://${publicHost}"
              "https://${buildHost}"
            ];
            webhook_secret_encryption_key_file = secret "webhook-encryption-key";
          };

          ui.brand_subtitle = "Nix CI (trial next to nixbot)";

          evaluator = {
            github_token_file = lib.mkIf cfg.githubApp.enable githubTokenFile;
            # Pure, restricted evaluation like nixbot's. With an impure one, the
            # lazyvim-nix module stats ~/.config at eval time (README.md).
            restrict_eval = true;
            allow_ifd = true;
            auto_allowed_uris = true;
            require_locked_flake = true;
            max_concurrent_evals = 1;
            eval_workers = 1;
            # circusJobs (about 245 attributes, 26 hosts) on a shared host.
            nix_timeout = 60 * 60;
            # Some large desktop evaluations exhaust a 16 GiB worker.
            memory_limit_mb = 20480;
            # aarch64 only once the GitHub Actions agents exist.
            systems = [ "x86_64-linux" ] ++ lib.optional cfg.githubActionsAgents.enable "aarch64-linux";
            # Also count paths niks3 (s3://nix-cache-brkn-lol in nix.conf)
            # already has as substitutable, signing the lookups with the
            # Circus S3 key (same project); the key id comes from the env.
            s3_substituters = lib.mkIf cfg.s3Upload.enable {
              secret_access_key_file = secret "s3/secret-access-key";
            };
          };

          queue_runner = {
            # Agents only (see allowLocalBuilds).
            workers = 0;
            local_systems = [ ];
            build_timeout = 12 * 60 * 60;
            scheduling_strategy = "dynamic";
            # Stop dispatching to a builder under pressure, so nixbot's builds
            # on the shared nodes keep priority.
            psi_threshold = 60.0;
            rpc = {
              # Reachable only on the trusted tailnet interfaces; the public
              # firewall does not open it.
              bind = "[::]:${toString rpcPort}";
              # TLS with the tailnet vhost's ACME certificate (DNS-01), which
              # agents verify against the system roots: GitHub Actions agents
              # send their OIDC token across this, and Circus refuses a
              # plaintext runner URL for them. The certificate is loaded at
              # start; renewals restart the queue-runner (security.acme below).
              tls = {
                cert_file = "${tailnetCertDir}/fullchain.pem";
                key_file = "${tailnetCertDir}/key.pem";
              };
              cache_substituter = "https://${tailnetHost}/nix-cache/";
              cache_public_key = cfg.settings.signing.public_key;
            }
            // lib.optionalAttrs cfg.githubActionsAgents.enable {
              oidc = {
                issuer = "https://token.actions.githubusercontent.com";
                audiences = [ "circus-agent" ];
                allowed_repositories = [ "pschmitt/nixos-config" ];
                allowed_subject_prefixes = [ "repo:pschmitt/nixos-config:ref:refs/heads/main" ];
                allowed_workflow_refs = [
                  "pschmitt/nixos-config/.github/workflows/circus-builder.yml@refs/heads/main"
                ];
              };
            };
            ephemeral_pools = lib.optional cfg.githubActionsAgents.enable (
              {
                name = "gha-aarch64-linux";
                allowed_build_repositories = [ "pschmitt/nixos-config" ];
                systems = [ "aarch64-linux" ];
                supported_features = [ "big-parallel" ];
                max_jobs = 2;
                max_inflight = 4;
                github_actions = {
                  workflow_repository = "pschmitt/nixos-config";
                  workflow = "circus-builder.yml";
                  ref_name = "main";
                  # The App's installation token (Actions: write) is minted every
                  # 45 minutes; Circus reads it on every dispatch (runtimeFiles).
                  token_file = if cfg.githubApp.enable then githubTokenFile else secret "github-dispatch-token";
                  runner_url = runnerUrl;
                  oidc_audience = "circus-agent";
                  agent_binary_url = "${cfg.githubActionsAgents.agentBinaryUrl}#sha256=${cfg.githubActionsAgents.agentBinarySha256}";
                };
              }
              // lib.optionalAttrs cfg.qemuOverflow.enable {
                qemu_overflow = {
                  agent_name = "circus-qemu";
                  system = "aarch64-linux";
                  supported_features = [ ];
                  allowed_build_repositories = [ "pschmitt/nixos-config" ];
                  grace_secs = 120;
                  status_file = qemuOverflowStatusPath;
                  status_ttl_secs = 90;
                };
              }
            );
          };

          cache = {
            enabled = true;
            cache_url = "https://${tailnetHost}/nix-cache/";
          };

          signing = {
            enabled = true;
            key_file = secret "cache-signing-key";
            # Public half of circus/cache-signing-key.
            public_key = "circus.brkn.lol-1:rib6EG6ItgQJbo9J+P5pNw6FK5UG9VzW0foZyhXlyeg=";
          };

          cache_upload = lib.mkIf cfg.s3Upload.enable {
            enabled = true;
            # niks3's bucket, under its own prefix: Circus never writes the
            # bucket root niks3 serves, and both garbage collectors only
            # delete keys from their own database, never by listing.
            store_uri = "s3://nix-cache-brkn-lol";
            compression = "zstd";
            s3 = {
              # Same OpenStack RGW as niks3 (region as its S3 location API says).
              region = "default";
              prefix = "circus";
              endpoint_url = "https://s3.openstack.de-west-01.wiit-cloud.io";
              use_path_style = true;
              secret_access_key_file = secret "s3/secret-access-key";
            };
          };

          notifications = lib.mkIf cfg.githubStatuses.enable (
            {
              enable_retry_queue = true;
            }
            // lib.optionalAttrs (cfg.githubApp.enable && cfg.githubWebhook.enable) {
              github_pr_comments = true;
              circus_base_url = "https://${publicHost}";
            }
            // lib.optionalAttrs (!cfg.githubApp.enable) {
              github_token_file = secret "github-status-token";
            }
          );

          declarative = {
            projects =
              map
                (
                  project:
                  project
                  // {
                    webhooks = lib.optional cfg.githubWebhook.enable {
                      forge_type = "github";
                      secret_file = secret "github-webhook-secret";
                    };
                  }
                )
                (
                  [
                    {
                      name = "nixos-config";
                      repository_url = repositoryUrl;
                      jobsets = [
                        {
                          name = "main";
                          nix_expression = "circusJobs";
                          branch = "main";
                          only_build_latest = true;
                        }
                      ];
                    }
                  ]
                  ++ import ./pilot-projects.nix
                );
            api_keys = [
              {
                name = "admin";
                role = "admin";
                key_file = secret "admin-api-key";
              }
            ]
            ++ lib.optional cfg.rworkerPool.enable {
              # Demand checks of the rworker pool autoscaler: read only.
              name = "rworker-autoscaler";
              role = "read-only";
              key_file = secret "autoscaler-api-key";
            };
            # Dashboard login (rbw entry circus.brkn.lol); the server applies
            # Circus' password policy to it.
            users = [
              {
                username = "pschmitt";
                email = "pschmitt@${config.domains.main}";
                full_name = "Philipp Schmitt";
                role = "admin";
                password_file = secret "users/pschmitt-password";
              }
            ];
          };
        };
      };

      nginx.virtualHosts = {
        ${publicHost} = {
          enableACME = true;
          forceSSL = true;
          authelia = {
            enable = true;
            # The authz endpoint is on another host: resolve it at runtime.
            resolver.addresses =
              if config.networking.nameservers != [ ] then config.networking.nameservers else [ "127.0.0.53" ];
          };
          locations = {
            "/" = {
              proxyPass = "http://127.0.0.1:${toString serverPort}";
              proxyWebsockets = true;
            };
          }
          // lib.optionalAttrs cfg.githubWebhook.enable {
            # GitHub cannot log in; Circus checks the HMAC signature.
            "/api/v1/webhooks/" = {
              proxyPass = "http://127.0.0.1:${toString serverPort}";
              authelia = false;
            };
          };
        };

        ${buildHost} = {
          enableACME = true;
          forceSSL = true;
          authelia = {
            enable = true;
            resolver.addresses =
              if config.networking.nameservers != [ ] then config.networking.nameservers else [ "127.0.0.53" ];
          };
          locations =
            dashboardLocations false
            // {
              # Topcoat opens its WebSocket on the origin root.
              "= /" =
                let
                  live = dashboardLocation false "GET" "/_build-live";
                in
                live
                // {
                  extraConfig = live.extraConfig + ''
                    if ($http_upgrade != "websocket") { return 302 /dash; }
                  '';
                };
            }
            // lib.optionalAttrs ((config.services.circus.settings.oauth.oidc or { }) ? authelia) {
              "= /api/v1/auth/oidc/authelia" = dashboardLocation false "GET" "";
              "= /api/v1/auth/oidc/authelia/callback" =
                let
                  callback = dashboardLocation false "GET" "";
                in
                callback
                // {
                  extraConfig = callback.extraConfig + "access_log off;\n";
                };
              # Keep existing-account linking behind Authelia during migration.
              "= /account" = dashboardLocation false "GET" "";
              "= /account/link/authelia" = dashboardLocation false "GET POST" "";
            };
        };

        # Binary cache for agents: tailnet clients only, no SSO (Nix cannot
        # log in). The server only serves paths Circus built or evaluated.
        ${tailnetHost} = {
          enableACME = true;
          forceSSL = true;
          authelia = {
            enable = true;
            resolver.addresses =
              if config.networking.nameservers != [ ] then config.networking.nameservers else [ "127.0.0.53" ];
          };
          locations =
            dashboardLocations true
            // {
              # The build dashboard forwards its root WebSocket to the
              # restricted renderer. Ordinary requests cannot use this route.
              "= /_build-live" =
                let
                  live = dashboardLocation true "GET" "/_build-live";
                in
                live
                // {
                  extraConfig = live.extraConfig + ''
                    if ($http_upgrade != "websocket") { return 404; }
                  '';
                };
              "/nix-cache/" = {
                proxyPass = "http://127.0.0.1:${toString serverPort}";
                authelia = false;
                extraConfig = ''
                  ${lib.concatMapStrings (range: "allow ${range};\n") tailnetRanges}
                  deny all;
                '';
              };
              "~ ^/job/nixos-config/main/hosts\\.[a-z0-9-]+/latest$" = {
                proxyPass = "http://127.0.0.1:${toString serverPort}";
                authelia = false;
                extraConfig = ''
                  ${lib.concatMapStrings (range: "allow ${range};\n") tailnetRanges}
                  deny all;
                  if ($arg_commit !~ "^[0-9a-f]{40}$") { return 400; }
                '';
              };
            }
            // lib.optionalAttrs cfg.rworkerPool.enable {
              # The pool autoscaler's demand check (API key required).
              "= /api/v1/operator/queue" = {
                proxyPass = "http://127.0.0.1:${toString serverPort}";
                extraConfig = ''
                  ${lib.concatMapStrings (range: "allow ${range};\n") tailnetRanges}
                  deny all;
                '';
              };
            };
        };
      };

      monit.checks = {
        circus-github-token = lib.mkIf cfg.githubApp.enable {
          type = "file";
          path = githubTokenFile;
          group = "services";
          restartUnit = "circus-github-token";
          conditions = ''
            if timestamp > 70 minutes then restart
            if 3 restarts within 10 cycles then alert
          '';
        };
        circus-server = {
          type = "host";
          address = "127.0.0.1";
          group = "services";
          restartUnit = "circus-server";
          # /health also depends on evaluator and queue-runner heartbeats.
          # Check the listener so their startup cannot restart the server.
          conditions = ''
            if failed
              port ${toString serverPort}
              with timeout 15 seconds
              for 3 cycles
            then restart
            if 3 restarts within 15 cycles then alert
          '';
        };
        circus-queue-runner = {
          type = "program";
          path = "${pkgs.systemd}/bin/systemctl is-active circus-queue-runner";
          group = "services";
          restartUnit = "circus-queue-runner";
          conditions = ''
            if status > 0 for 3 cycles then restart
            if 3 restarts within 15 cycles then alert
          '';
        };
        circus-evaluator = {
          type = "program";
          path = "${pkgs.systemd}/bin/systemctl is-active circus-evaluator";
          group = "services";
          restartUnit = "circus-evaluator";
          conditions = ''
            if status > 0 for 3 cycles then restart
            if 3 restarts within 15 cycles then alert
          '';
        };
      };
    };

    # The queue-runner's RPC serves the tailnet vhost's certificate: restart it
    # on renewal, since Circus loads the certificate once at start.
    security.acme.certs.${tailnetHost}.reloadServices = [ "circus-queue-runner.service" ];

    systemd.services = lib.mkMerge [
      {
        circus-server.serviceConfig = {
          EnvironmentFile = config.sops.templates."circus-server.env".path;
          MemoryMax = "2G";
        };
        circus-queue-runner.serviceConfig = {
          EnvironmentFile = config.sops.templates."circus-queue-runner.env".path;
          # Verifies and signs agent outputs (downloads uploaded NARs back).
          MemoryMax = "4G";
          CPUQuota = "200%";
        };
        circus-evaluator = {
          environment = {
            NIX_CONFIG = "pure-eval = true";
          }
          // lib.optionalAttrs (gitlabNixConf != null) {
            NIX_USER_CONF_FILES = "/run/credentials/circus-evaluator.service/nix-gitlab";
          };
          serviceConfig = {
            EnvironmentFile = config.sops.templates."circus-evaluator.env".path;
            # Reads the system nix.conf's private-GitHub token include
            # (profiles/base/nix/secrets.nix, group nix-access-tokens).
            SupplementaryGroups = [ "nix-access-tokens" ];
            LoadCredential = lib.optional (gitlabNixConf != null) "nix-gitlab:${gitlabNixConf}";
            # Leave room for the evaluator's coordinator and the 20 GiB
            # worker while nixbot and Circus agents share this host.
            MemoryHigh = "22G";
            MemoryMax = "26G";
            CPUQuota = "800%";
            CPUWeight = 100;
            IOWeight = 50;
          };
        };
      }

      (lib.mkIf cfg.githubApp.enable (
        {
          circus-github-token = {
            description = "Mint a GitHub App installation token for Circus";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            # Refresh before the notifying services start, without making them
            # depend on GitHub: a failed mint only delays statuses.
            before = map (unit: "${unit}.service") notifyingUnits;
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.escapeShellArgs [
                (lib.getExe githubTokenMinter)
                (secret "github-app/app-id")
                (secret "github-app/private-key")
                cfg.githubApp.repository
                githubTokenFile
              ];
              TimeoutStartSec = "2min";
              # root reads the SOPS key; the token goes to root:circus-github-token 0440.
              Group = githubTokenGroup;
              RuntimeDirectory = baseNameOf githubTokenDir;
              RuntimeDirectoryMode = "0750";
              RuntimeDirectoryPreserve = "yes";
              UMask = "0227";
              NoNewPrivileges = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ReadWritePaths = [ githubTokenDir ];
            };
          };
        }
        // lib.genAttrs notifyingUnits (_: {
          wants = [ "circus-github-token.service" ];
          # Read on every status by pschmitt/circus, so rotations apply live.
          environment.CIRCUS_NOTIFICATIONS__GITHUB_TOKEN_FILE = githubTokenFile;
          serviceConfig.SupplementaryGroups = [ githubTokenGroup ];
        })
      ))
    ];

    systemd.timers.circus-github-token = lib.mkIf cfg.githubApp.enable {
      description = "Refresh Circus' GitHub App installation token";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        # Installation tokens live one hour.
        OnUnitActiveSec = "45min";
        RandomizedDelaySec = "1min";
      };
    };

    users.groups = {
      ${githubTokenGroup} = lib.mkIf cfg.githubApp.enable { };
      # Owned by profiles/base/nix/secrets.nix; declared here too so the
      # evaluator's membership does not depend on which lands first.
      nix-access-tokens = { };
    };
  };
}
