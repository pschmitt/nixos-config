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
  tailnetHost = "circus.${hostName}.${config.domains.netbird}";

  serverPort = 3000;
  rpcPort = 8443;

  secret = name: config.sops.secrets."circus/${name}".path;
  placeholder = name: config.sops.placeholder."circus/${name}";

  # NetBird and Tailscale (trusted interfaces on the build nodes): the
  # tailnet vhost only answers clients from these ranges.
  tailnetRanges = [
    "100.64.0.0/10"
    "fd7a:115c:a1e0::/48"
    "fd8d:fa54:9081::/48"
  ];

  s3KeyIdEnv = lib.optionalString cfg.s3Upload.enable ''
    CIRCUS_CACHE_UPLOAD__S3__ACCESS_KEY_ID=${placeholder "s3/access-key-id"}
  '';
in
{
  imports = [
    inputs.circus.nixosModules.circus
    ./agent.nix
  ];

  options.services.circus = {
    allowLocalBuilds = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow the queue-runner to build on this host. Off: every build goes to
        an agent, enforced by an assertion.
      '';
    };

    githubStatuses.enable = lib.mkEnableOption ''
      commit statuses (context circus/<job>) on GitHub, using the token in
      the host secret circus/github-status-token
    '';

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
    };
  };

  config = {
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
        # Nix cache signing key (`nix key generate-secret`); public half below.
        "circus/cache-signing-key" = config.sops.mkHostSecret { };
        "circus/webhook-encryption-key" = config.sops.mkHostSecret { };
        # SHA-256 of circus/agent-join-token (./agent.nix).
        "circus/agent-join-token-sha256" = config.sops.mkHostSecret { };
      }
      // lib.optionalAttrs cfg.githubWebhook.enable {
        "circus/github-webhook-secret" = config.sops.mkHostSecret { };
      }
      // lib.optionalAttrs cfg.githubStatuses.enable {
        # Fine-grained token: commit statuses read/write on pschmitt/nixos-config.
        "circus/github-status-token" = config.sops.mkHostSecret { };
      }
      // lib.optionalAttrs cfg.s3Upload.enable {
        "circus/s3/access-key-id" = config.sops.mkHostSecret { };
        "circus/s3/secret-access-key" = config.sops.mkHostSecret { };
      }
      // lib.optionalAttrs cfg.githubActionsAgents.enable {
        # Fine-grained token: actions read/write on pschmitt/nixos-config.
        "circus/github-dispatch-token" = config.sops.mkHostSecret { };
      };

      # Values without a *_file setting reach Circus as CIRCUS_A__B
      # environment overrides, so they never land in the Nix store. Only the
      # queue-runner reads [queue_runner]: the server would reject a partial
      # rpc table.
      templates = {
        "circus-queue-runner.env".content = ''
          CIRCUS_QUEUE_RUNNER__RPC__JOIN_TOKENS="[{ name = 'rofl', token_hash = '${placeholder "agent-join-token-sha256"}' }]"
        ''
        + s3KeyIdEnv;
        # The server presigns S3 GETs for cache downloads.
        "circus-server.env".content = s3KeyIdEnv;
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

        settings = {
          server = {
            host = "127.0.0.1";
            port = serverPort;
            # nginx terminates TLS (publicHost).
            force_secure_cookies = true;
            allowed_origins = [ "https://${publicHost}" ];
            webhook_secret_encryption_key_file = secret "webhook-encryption-key";
          };

          ui.brand_subtitle = "Nix CI (trial next to nixbot)";

          evaluator = {
            # Pure, restricted evaluation like nixbot's. With an impure one, the
            # lazyvim-nix module stats ~/.config at eval time (README.md).
            restrict_eval = true;
            allow_ifd = true;
            auto_allowed_uris = true;
            require_locked_flake = true;
            max_concurrent_evals = 1;
            eval_workers = 2;
            # Per evaluator process; the desktop hosts need about 7.2 GiB.
            memory_limit_mb = 10240;
            # aarch64 only once the GitHub Actions agents exist.
            systems = [ "x86_64-linux" ] ++ lib.optional cfg.githubActionsAgents.enable "aarch64-linux";
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
              # Plain TCP inside WireGuard (NetBird/Tailscale).
              allow_plaintext = true;
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
            ephemeral_pools = lib.optional cfg.githubActionsAgents.enable {
              name = "gha-aarch64-linux";
              allowed_build_repositories = [ "pschmitt/nixos-config" ];
              systems = [ "aarch64-linux" ];
              max_jobs = 2;
              max_inflight = 4;
              github_actions = {
                workflow_repository = "pschmitt/nixos-config";
                workflow = "circus-builder.yml";
                ref_name = "main";
                token_file = secret "github-dispatch-token";
                runner_url = "circus://${hostName}.${config.domains.netbird}:${toString rpcPort}";
                oidc_audience = "circus-agent";
                agent_binary_url = cfg.githubActionsAgents.agentBinaryUrl;
              };
            };
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
            store_uri = "s3://circus-cache-brkn-lol";
            compression = "zstd";
            s3 = {
              # Same OpenStack RGW as niks3 (region as its S3 location API says).
              region = "default";
              prefix = "nix-cache";
              endpoint_url = "https://s3.openstack.de-west-01.wiit-cloud.io";
              use_path_style = true;
              secret_access_key_file = secret "s3/secret-access-key";
            };
          };

          notifications = lib.mkIf cfg.githubStatuses.enable {
            github_token_file = secret "github-status-token";
            enable_retry_queue = true;
          };

          declarative = {
            projects = [
              {
                name = "nixos-config";
                repository_url = "https://github.com/pschmitt/nixos-config";
                jobsets = [
                  {
                    name = "main";
                    nix_expression = "herculesCI.onPush.default.outputs";
                    branch = "main";
                    only_build_latest = true;
                  }
                ];
                webhooks = lib.optional cfg.githubWebhook.enable {
                  forge_type = "github";
                  secret_file = secret "github-webhook-secret";
                };
              }
            ];
            api_keys = [
              {
                name = "admin";
                role = "admin";
                key_file = secret "admin-api-key";
              }
            ];
            users = [ ];
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

        # Binary cache for agents: tailnet clients only, no SSO (Nix cannot
        # log in). The server only serves paths Circus built or evaluated.
        ${tailnetHost} = {
          enableACME = true;
          forceSSL = true;
          locations = {
            "/".return = "404";
            "/nix-cache/" = {
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
        circus-server = {
          type = "host";
          address = "127.0.0.1";
          group = "services";
          restartUnit = "circus-server";
          conditions = ''
            if failed
              port ${toString serverPort}
              protocol http request "/health" status 200
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

    systemd.services = {
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
        environment.NIX_CONFIG = "pure-eval = true";
        serviceConfig = {
          # Next to nixbot's remote evaluation (up to 2 x 2 x 8 GiB) and its
          # 16 build slots on this 62 GiB / 32 core host.
          MemoryHigh = "12G";
          MemoryMax = "16G";
          CPUQuota = "400%";
          CPUWeight = 50;
          IOWeight = 50;
        };
      };
    };

  };
}
