{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hermesHost = "hermes.${config.domains.main}";
  aiHost = "ai.${config.domains.main}";
  matrixUser = "@pschmitt:matrix.${config.domains.main}";
  dashboardPort = 9119;
  signalCliPort = 8712;
  signalCliDataDir = "${config.services.hermes-agent.stateDir}/.signal-cli";
  gpgHome = "${config.services.hermes-agent.stateDir}/.gnupg";
  ghConfigRoot = "${config.services.hermes-agent.stateDir}/.config/gh";
  sopsAgeKeyFile = config.sops.secrets."age/hermes-sops/keys.txt".path;
  hermesOpsDir = "${config.services.hermes-agent.stateDir}/ops";
  hermesNixFlakeDir = "${config.services.hermes-agent.workingDirectory}/nixos-config";

  # Upstream packaging bug (NousResearch/hermes-agent pyproject.toml,
  # [tool.setuptools] py-modules): registration_lifecycle.py exists at the
  # repo root and is imported (unguarded, module-level) by
  # hermes_cli/plugins.py, but py-modules never got it added alongside its
  # sibling utils/hermes_constants/etc, so uv2nix's sealed venv never
  # installs it -- `hermes dashboard` crash-loops with "ModuleNotFoundError:
  # No module named 'registration_lifecycle'". The module only imports
  # stdlib, so a plain PYTHONPATH supplement is sufficient until the
  # one-line py-modules fix lands upstream.
  hermesRegistrationLifecycleShim = pkgs.runCommand "hermes-registration-lifecycle-shim" { } ''
    mkdir -p $out
    cp ${inputs.hermes-agent}/registration_lifecycle.py $out/
  '';
  ghBrknLol = pkgs.writeShellScriptBin "gh-brkn-lol" ''
    export GH_CONFIG_DIR="${ghConfigRoot}/gh-brkn-lol"
    export GH_TOKEN="''${GH_BRKN_LOL_TOKEN:?GH_BRKN_LOL_TOKEN is not set}"
    exec ${pkgs.gh}/bin/gh "$@"
  '';
  ghPschmitt = pkgs.writeShellScriptBin "gh-pschmitt" ''
    export GH_CONFIG_DIR="${ghConfigRoot}/pschmitt"
    export GH_TOKEN="''${GH_PSCHMITT_TOKEN:?GH_PSCHMITT_TOKEN is not set}"
    exec ${pkgs.gh}/bin/gh "$@"
  '';
  autheliaConfig = import ./authelia-nginx-config.nix { inherit config; };

  # Import every agentskills.io-compatible shared skill. This keeps Hermes in
  # sync with Home Manager without an ever-growing per-skill mapping here.
  sharedSkillsPath = ../home-manager/devel/skills;
  hermesSkills = pkgs.linkFarm "hermes-skills" (
    lib.mapAttrsToList
      (name: _: {
        inherit name;
        path = sharedSkillsPath + "/${name}";
      })
      (
        lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists (sharedSkillsPath + "/${name}/SKILL.md")
        ) (builtins.readDir sharedSkillsPath)
      )
    ++ [
      {
        name = "todoist-cli";
        path = pkgs.todoist-cli.skill;
      }
    ]
  );

  bitwardenMcp = pkgs.buildNpmPackage {
    pname = "bitwarden-mcp-server";
    version = "2026.7.0";
    src = inputs.bitwarden-mcp;
    nodejs = pkgs.nodejs_22;
    npmDepsHash = "sha256-rCK8vaZdsyOLgWRub54exa8TTgB7NeXjDnhlz5DBTOY=";
  };

  bitwardenCliDataPath = "${config.services.hermes-agent.stateDir}/.bitwarden-cli/data.json";
  hermesNixosApply = pkgs.writeShellApplication {
    name = "hermes-nixos-apply";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./scripts/hermes-nixos-apply.sh;
  };
  hermesNixosInit = pkgs.writeShellApplication {
    name = "hermes-nixos-init";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      ghBrknLol
    ];
    text = builtins.readFile ./scripts/hermes-nixos-init.sh;
  };
  hermesMountHa = pkgs.writeShellApplication {
    name = "hermes-mount-ha";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      exec systemctl start --no-block mnt-ha.mount
      # vim: set ft=sh et ts=2 sw=2 :
    '';
  };
  hermesOpsDispatch = pkgs.writeShellApplication {
    name = "hermes-ops-dispatch";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.nix
      pkgs.nixos-rebuild
      pkgs.systemd
      pkgs.util-linux
    ];
    text = builtins.readFile ./scripts/hermes-ops-dispatch.sh;
  };
in
{
  imports = [
    inputs.hermes-agent.nixosModules.default
  ];

  security.sudo.extraRules = [
    {
      users = [ config.services.hermes-agent.user ];
      commands = [
        {
          command = "/run/current-system/sw/bin/hermes-mount-ha";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  sops = {
    # `home-assistant/token` is the canonical Home Assistant token name. The
    # Home Manager declaration reads it from each host's SOPS file and gives
    # it to the logged-in user; this service declaration reads the shared
    # copy only to render the root-owned Hermes environment file.
    # `hermes/home-assistant/llat` is a separate LLAT stored in rofl-10's
    # SOPS file and must be owned by the Hermes service account.
    secrets = {
      "n8n/mcp/token" = {
        sopsFile = ../secrets/shared.sops.yaml;
        mode = "0400";
      };
      "home-assistant/token" = {
        sopsFile = ../secrets/shared.sops.yaml;
        mode = "0400";
      };
      "hermes/home-assistant/llat" = config.custom.mkSecret {
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "hermes/matrix/password" = config.custom.mkSecret {
        mode = "0400";
      };
      "hermes/matrix/recovery-key" = config.custom.mkSecret {
        mode = "0400";
      };
      "hermes/bitwarden/session" = config.custom.mkSecret {
        mode = "0400";
      };
      "hermes/bitwarden/data-json" = config.custom.mkSecret {
        mode = "0400";
      };
      "hermes/github/pschmitt/token" = config.custom.mkSecret {
        mode = "0400";
      };
      "hermes/github/gh-brkn-lol/token" = config.custom.mkSecret {
        mode = "0400";
      };
      "hermes/signal/account" = config.custom.mkSecret {
        mode = "0400";
      };
      "hermes/signal/allowed-users" = config.custom.mkSecret {
        mode = "0400";
      };
      "ssh/nix-remote-builder/privkey" = {
        sopsFile = ../secrets/shared.sops.yaml;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "todoist/api_token" = {
        sopsFile = ../secrets/shared.sops.yaml;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "todoist/user_id" = {
        sopsFile = ../secrets/shared.sops.yaml;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "todoist/email" = {
        sopsFile = ../secrets/shared.sops.yaml;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "gpg/hermes/privateKey" = {
        sopsFile = ../hosts/rofl-10/secrets.sops.yaml;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "gpg/hermes/passphrase" = {
        sopsFile = ../hosts/rofl-10/secrets.sops.yaml;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "ssh/hermes-sops/privateKey" = {
        sopsFile = ../hosts/rofl-10/secrets.sops.yaml;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "age/hermes-sops/keys.txt" = {
        sopsFile = ../hosts/rofl-10/secrets.sops.yaml;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
    };
    templates = {
      "hermes/mcp.env" = {
        content = ''
          MCP_N8N_API_KEY=${config.sops.placeholder."n8n/mcp/token"}
          MCP_HOME_ASSISTANT_API_KEY=${config.sops.placeholder."home-assistant/token"}
          HERMES_AGENT_HELP_GUIDANCE=For GitHub interactions, prefer the gh-brkn-lol account by default: use the github-gh-brkn-lol MCP server or gh-brkn-lol command. Use the github-pschmitt MCP server or gh-pschmitt command only when the pschmitt account is specifically needed; verify identity before account-sensitive actions and do not switch credentials without explicit instruction. For host Nix changes, initialize the checkout with hermes-nixos-init if ${hermesNixFlakeDir} is missing, edit that checkout, run nixos-rebuild dry-build --flake ${hermesNixFlakeDir}#rofl-10, then run hermes-nixos-apply to request the privileged switch.
          HASS_URL=https://ha.${config.domains.main}
          HASS_TOKEN=${config.sops.placeholder."hermes/home-assistant/llat"}
          MATRIX_HOMESERVER=https://matrix-client.matrix.org
          MATRIX_PASSWORD=${config.sops.placeholder."hermes/matrix/password"}
          MATRIX_USER_ID=@hermes-brkn:matrix.org
          MATRIX_ALLOWED_USERS=@pschmitt:one.ems.host,${matrixUser}
          MATRIX_E2EE_MODE=required
          MATRIX_DEVICE_ID=HERMESROFL10
          MATRIX_RECOVERY_KEY=${config.sops.placeholder."hermes/matrix/recovery-key"}
          HERMES_BW_SESSION=${config.sops.placeholder."hermes/bitwarden/session"}
          GH_BRKN_LOL_TOKEN=${config.sops.placeholder."hermes/github/gh-brkn-lol/token"}
          GH_PSCHMITT_TOKEN=${config.sops.placeholder."hermes/github/pschmitt/token"}
          GH_TOKEN=${config.sops.placeholder."hermes/github/gh-brkn-lol/token"}
          SIGNAL_HTTP_URL=http://127.0.0.1:${toString signalCliPort}
          SIGNAL_ACCOUNT=${config.sops.placeholder."hermes/signal/account"}
          SIGNAL_ALLOWED_USERS=${config.sops.placeholder."hermes/signal/allowed-users"}
        '';
        mode = "0400";
        restartUnits = [
          "hermes-agent.service"
          "hermes-dashboard.service"
          "signal-cli-daemon.service"
        ];
      };
      "hermes/bitwarden/data.json" = {
        content = config.sops.placeholder."hermes/bitwarden/data-json";
        mode = "0400";
        restartUnits = [ "hermes-agent.service" ];
      };
      "todoist-cli/config.json" = {
        path = "${config.services.hermes-agent.stateDir}/.config/todoist-cli/config.json";
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        content = ''
          {
            "config_version": 2,
            "users": [
              {
                "id": "${config.sops.placeholder."todoist/user_id"}",
                "email": "${config.sops.placeholder."todoist/email"}",
                "auth_mode": "unknown",
                "api_token": "${config.sops.placeholder."todoist/api_token"}"
              }
            ],
            "user": {
              "defaultUser": "${config.sops.placeholder."todoist/user_id"}"
            }
          }
        '';
        mode = "0400";
        restartUnits = [ "hermes-agent.service" ];
      };
    };
  };

  services = {
    hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      stateDir = "/srv/hermes";
      workingDirectory = "/srv/hermes/workspace";
      extraPackages = [
        pkgs.gh
        pkgs.gnupg
        pkgs.sops
        pkgs.ssh-to-age
        pkgs.nix
        pkgs.nixos-rebuild
        pkgs.todoist-cli
        pkgs.tmux
        hermesNixosApply
        hermesNixosInit
        hermesMountHa
        ghBrknLol
        ghPschmitt
      ]
      ++ (with pkgs.llm-agents; [
        claude-code
        codex
      ]);
      settings = {
        model = {
          provider = "openai-codex";
          default = "gpt-5.6-luna";
        };
        tool_loop_guardrails = {
          hard_stop_enabled = true;
          hard_stop_after = {
            exact_failure = 5;
            idempotent_no_progress = 5;
          };
        };
        mcp_servers = {
          n8n = {
            url = "https://n8n.${config.domains.main}/mcp-server/http";
            headers.Authorization = "Bearer \${MCP_N8N_API_KEY}";
            connect_timeout = 30;
            timeout = 90;
          };
          home-assistant = {
            url = "https://ha.${config.domains.main}/api/mcp";
            headers.Authorization = "Bearer \${MCP_HOME_ASSISTANT_API_KEY}";
            connect_timeout = 30;
            timeout = 90;
          };
          bitwarden = {
            command = "${bitwardenMcp}/bin/mcp-server-bitwarden";
            env = {
              BW_SESSION = "\${HERMES_BW_SESSION}";
              BW_CLI_PATH = "${pkgs.bitwarden-cli}/bin/bw";
              BITWARDENCLI_APPDATA_DIR = builtins.dirOf bitwardenCliDataPath;
              # Allow Bitwarden's attachment tools to operate within the Hermes
              # workspace while retaining systemd's filesystem sandbox.
              BW_ALLOWED_DIRECTORIES = config.services.hermes-agent.workingDirectory;
            };
            connect_timeout = 30;
            timeout = 90;
          };
          # hermes-agent's terminal/execute_code sandbox unconditionally strips
          # GH_TOKEN/GITHUB_TOKEN regardless of config (GHSA-rhgp-j443-p4rf), so
          # raw `gh` in a shell tool call never sees credentials. MCP servers
          # run in the main gateway process instead and aren't subject to that
          # strip, so GitHub access goes through the official MCP servers here.
          github-gh-brkn-lol = {
            command = "${pkgs.github-mcp-server}/bin/github-mcp-server";
            args = [
              "stdio"
              "--toolsets"
              "default,notifications"
            ];
            env = {
              GITHUB_PERSONAL_ACCESS_TOKEN = "\${GH_BRKN_LOL_TOKEN}";
            };
            connect_timeout = 30;
            timeout = 90;
          };
          github-pschmitt = {
            command = "${pkgs.github-mcp-server}/bin/github-mcp-server";
            args = [
              "stdio"
              "--toolsets"
              "default,notifications"
            ];
            env = {
              GITHUB_PERSONAL_ACCESS_TOKEN = "\${GH_PSCHMITT_TOKEN}";
            };
            connect_timeout = 30;
            timeout = 90;
          };
          playwright-rofl-13 = {
            command = "${pkgs.openssh}/bin/ssh";
            args = [
              "-o"
              "BatchMode=yes"
              "-o"
              "IdentitiesOnly=yes"
              "-o"
              "IdentityFile=${config.sops.secrets."ssh/nix-remote-builder/privkey".path}"
              "-o"
              "UserKnownHostsFile=/etc/ssh/ssh_known_hosts"
              "-l"
              "nix-remote-builder"
              "rofl-13"
              "${pkgs.playwright-mcp}/bin/playwright-mcp"
              "--cdp-endpoint=http://127.0.0.1:9222"
            ];
            connect_timeout = 30;
            timeout = 90;
          };
          playwright-rofl-14 = {
            command = "${pkgs.openssh}/bin/ssh";
            args = [
              "-o"
              "BatchMode=yes"
              "-o"
              "IdentitiesOnly=yes"
              "-o"
              "IdentityFile=${config.sops.secrets."ssh/nix-remote-builder/privkey".path}"
              "-o"
              "UserKnownHostsFile=/etc/ssh/ssh_known_hosts"
              "-l"
              "nix-remote-builder"
              "rofl-14"
              "${pkgs.playwright-mcp}/bin/playwright-mcp"
              "--cdp-endpoint=http://127.0.0.1:9222"
            ];
            connect_timeout = 30;
            timeout = 90;
          };
          playwright-fnuc = {
            command = "${pkgs.openssh}/bin/ssh";
            args = [
              "-o"
              "BatchMode=yes"
              "-o"
              "IdentitiesOnly=yes"
              "-o"
              "IdentityFile=${config.sops.secrets."ssh/nix-remote-builder/privkey".path}"
              "-o"
              "UserKnownHostsFile=/etc/ssh/ssh_known_hosts"
              "-l"
              config.mainUser.username
              "fnuc"
              "${pkgs.playwright-mcp}/bin/playwright-mcp"
              "--cdp-endpoint=http://127.0.0.1:9222"
            ];
            connect_timeout = 30;
            timeout = 90;
          };
        };
        skills.external_dirs = [ "${hermesSkills}" ];
      };
    };

    nginx.virtualHosts = {
      ${hermesHost} = {
        enableACME = false;
        useACMEHost = "wildcard.${config.domains.main}";
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        forceSSL = true;
        extraConfig = autheliaConfig.server;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString dashboardPort}";
          proxyWebsockets = true;
          # The module appends its recommended headers after extraConfig, which
          # would overwrite the loopback Host header Hermes requires.
          recommendedProxySettings = false;
          extraConfig = ''
            ${autheliaConfig.location}
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Server $hostname;
            # Hermes validates the Host header against its loopback binding.
            proxy_set_header Host 127.0.0.1;
            # Its WebSocket guard also validates the browser's Origin header.
            proxy_set_header Origin http://127.0.0.1;
          '';
        };
      };

      # Keep ai.brkn.lol as a convenient alias without maintaining a second
      # dashboard endpoint.
      ${aiHost} = {
        enableACME = false;
        useACMEHost = "wildcard.${config.domains.main}";
        # FIXME https://github.com/NixOS/nixpkgs/issues/210807
        acmeRoot = null;
        forceSSL = true;
        locations."/".return = "308 https://${hermesHost}$request_uri";
      };
    };

    monit.config = lib.mkAfter ''
      check host "hermes" with address "127.0.0.1"
        group container-services
        restart program = "${pkgs.systemd}/bin/systemctl restart hermes-dashboard.service"
          with timeout 180 seconds
        if failed
          port ${toString dashboardPort}
          protocol http
          request "/api/status"
          with timeout 90 seconds
        then restart
        if 5 restarts within 10 cycles then alert

      check host "hermes-signal-cli" with address "127.0.0.1"
        group container-services
        restart program = "${pkgs.systemd}/bin/systemctl restart signal-cli-daemon.service"
          with timeout 180 seconds
        if failed
          port ${toString signalCliPort}
          protocol http
          request "/api/v1/check"
          with timeout 90 seconds
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

  systemd = {
    services = {
      # hermes-agent.service itself (the gateway that actually answers
      # Signal/etc) is defined by the upstream module -- it hits the same
      # registration_lifecycle gap as hermes-dashboard below, via
      # gateway/run.py's _install_plugin_message_injector -> hermes_cli.plugins.
      hermes-agent.environment.PYTHONPATH = hermesRegistrationLifecycleShim;

      # The upstream module runs the gateway natively. Its dashboard is a
      # separate process, bound to loopback and protected by a two-factor
      # Authelia policy.
      hermes-dashboard = {
        description = "Hermes Agent Dashboard";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "hermes-agent.service"
        ];
        wants = [ "network-online.target" ];
        environment = {
          HOME = config.services.hermes-agent.stateDir;
          HERMES_HOME = "${config.services.hermes-agent.stateDir}/.hermes";
          HERMES_MANAGED = "true";
          PYTHONPATH = hermesRegistrationLifecycleShim;
        };
        serviceConfig = {
          User = config.services.hermes-agent.user;
          Group = config.services.hermes-agent.group;
          WorkingDirectory = config.services.hermes-agent.workingDirectory;
          ExecStart = "${config.services.hermes-agent.package}/bin/hermes dashboard --host 127.0.0.1 --port ${toString dashboardPort} --no-open";
          Restart = "always";
          RestartSec = 5;
          UMask = "0007";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = false;
          ReadWritePaths = [
            config.services.hermes-agent.stateDir
            config.services.hermes-agent.workingDirectory
          ];
          PrivateTmp = true;
          EnvironmentFile = config.sops.templates."hermes/mcp.env".path;
        };
        path = [
          config.services.hermes-agent.package
          pkgs.bash
          pkgs.coreutils
          pkgs.git
        ];
      };

      # signal-cli runs its own daemon (JSON-RPC over HTTP, loopback-only) that
      # the gateway's Signal adapter talks to; Hermes never calls the Signal
      # servers directly. Account registration/verification is a one-time
      # interactive step (needs a real SMS/voice code) run manually against the
      # same data dir.
      signal-cli-daemon = {
        description = "signal-cli JSON-RPC daemon for Hermes";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          User = config.services.hermes-agent.user;
          Group = config.services.hermes-agent.group;
          ExecStartPre = [
            "+${pkgs.coreutils}/bin/install -d -m 0700 -o ${config.services.hermes-agent.user} -g ${config.services.hermes-agent.group} ${signalCliDataDir}"
          ];
          # The bot's phone number is a secret (see hermes/signal/account), so
          # read it from the environment at runtime instead of baking it into
          # the unit.
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.signal-cli}/bin/signal-cli --scrub-log -a \"$SIGNAL_ACCOUNT\" -d ${signalCliDataDir} daemon --http 127.0.0.1:${toString signalCliPort} --receive-mode on-start'";
          EnvironmentFile = [ config.sops.templates."hermes/mcp.env".path ];
          Restart = "always";
          RestartSec = 5;
          UMask = "0077";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = false;
          # ReadWritePaths must point at a path that already exists on the host
          # when the unit's mount namespace is set up (before ExecStartPre
          # runs), so this targets the stateDir itself rather than the
          # not-yet-created .signal-cli subdirectory.
          ReadWritePaths = [ config.services.hermes-agent.stateDir ];
          PrivateTmp = true;
        };
      };

      hermes-agent = {
        after = [ "signal-cli-daemon.service" ];
        wants = [ "signal-cli-daemon.service" ];
        environment = {
          GNUPGHOME = gpgHome;
          SOPS_AGE_KEY_FILE = sopsAgeKeyFile;
        };
        path = [
          pkgs.bash
          pkgs.coreutils
          pkgs.curl
          pkgs.gh
          pkgs.git
          pkgs.jq
          ghBrknLol
          ghPschmitt
        ];
        serviceConfig = {
          EnvironmentFile = [ config.sops.templates."hermes/mcp.env".path ];
          # The Bitwarden CLI needs its account profile alongside BW_SESSION.
          # Keep the SOPS-rendered source root-only and give the Hermes user a
          # private, writable runtime copy for vault mutations and syncs.
          ExecStartPre = [
            "${pkgs.coreutils}/bin/install -d -m 0700 ${gpgHome}"
            "${pkgs.coreutils}/bin/install -d -m 0700 ${ghConfigRoot}/gh-brkn-lol ${ghConfigRoot}/pschmitt"
            "${pkgs.gnupg}/bin/gpg --batch --yes --homedir ${gpgHome} --pinentry-mode loopback --passphrase-file ${
              config.sops.secrets."gpg/hermes/passphrase".path
            } --import ${config.sops.secrets."gpg/hermes/privateKey".path}"
            "+${pkgs.coreutils}/bin/install -d -m 0700 -o ${config.services.hermes-agent.user} -g ${config.services.hermes-agent.group} ${builtins.dirOf bitwardenCliDataPath}"
            "+${pkgs.coreutils}/bin/install -D -m 0600 -o ${config.services.hermes-agent.user} -g ${config.services.hermes-agent.group} ${
              config.sops.templates."hermes/bitwarden/data.json".path
            } ${bitwardenCliDataPath}"
          ];
          # Keep the optional SSHFS mount writable when it is present without
          # resolving its automount while this service's namespace is created.
          ProtectSystem = lib.mkForce "full";
        };
      };
      hermes-ops = {
        description = "Privileged operations requested by Hermes";
        environment = {
          HERMES_FLAKE_DIR = hermesNixFlakeDir;
          HERMES_GROUP = config.services.hermes-agent.group;
          HERMES_OPS_DIR = hermesOpsDir;
          HERMES_USER = config.services.hermes-agent.user;
          NIXOS_REBUILD = pkgs.nixos-rebuild;
        };
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          ExecStart = "${hermesOpsDispatch}/bin/hermes-ops-dispatch";
          # This service intentionally performs the host switch as root. Keep
          # Hermes itself sandboxed and make this dispatcher the only privileged
          # operation path exposed to it.
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = false;
          ProtectSystem = "off";
          TimeoutStartSec = "30min";
        };
      };
    };

    paths.hermes-ops = {
      description = "Watch for privileged operations requested by Hermes";
      wantedBy = [ "paths.target" ];
      pathConfig = {
        PathChanged = hermesOpsDir + "/request";
        Unit = "hermes-ops.service";
      };
    };

    tmpfiles.rules = [
      "d ${hermesOpsDir} 0700 ${config.services.hermes-agent.user} ${config.services.hermes-agent.group} - -"
    ];
  };

  # Require Authelia before proxying, including from the mesh. The dashboard
  # itself is loopback-only, so NGINX is its only external entry point.
  custom.authelia.extraTwoFactorDomains = [ hermesHost ];
}
