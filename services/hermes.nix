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
  hermesApiPort = 8642;
  hermesHaMcpPort = 9585;
  signalCliDataDir = "${config.services.hermes-agent.stateDir}/.signal-cli";
  gpgHome = "${config.services.hermes-agent.stateDir}/.gnupg";
  ghConfigRoot = "${config.services.hermes-agent.stateDir}/.config/gh";
  rofl10SecretsFile = inputs.nixos-config-private.outPath + "/hosts/rofl-10/secrets.sops.yaml";
  sopsAgeKeyFile = config.sops.secrets."age/hermes-sops/keys.txt".path;
  hermesOpsDir = "${config.services.hermes-agent.stateDir}/ops";
  hermesNixFlakeDir = "${config.services.hermes-agent.workingDirectory}/nixos-config";

  # Upstream's flake never passes `version` to nix/hermes-agent.nix, so the
  # install stamp reports baseVersion "0.0.0" and every plugin gated by
  # `requires_hermes` (e.g. the homeassistant plugin, which left core) refuses
  # to install: "requires hermes >=0.21.5, running 0.0.0". Stamp the latest
  # release tag reachable from the locked hermes-agent rev; bump it alongside
  # the flake input.
  hermesVersion = "0.23.2";
  # Hermes applies a patch for patchelf 0.19.2 to its pinned binaries. Nixpkgs
  # currently supplies 0.15.2, where that patch does not apply. Remove when
  # Hermes handles the selected patchelf version itself. Reviewed 2026-11-10
  # at Nixpkgs f4a03c008967841f2a0b3cb7c436fc6fc31671f6; Node and npm start.
  hermesPatchelf = pkgs.patchelf.overrideAttrs (_: {
    version = "0.19.2";
    src = pkgs.fetchurl {
      url = "https://github.com/NixOS/patchelf/releases/download/0.19.2/patchelf-0.19.2.tar.bz2";
      hash = "sha256-1K2aTlxongkRnOLzCpSw6LT5jHhZASPqIWZeNMaSiAE=";
    };
  });
  hermesPmPackages = lib.filterAttrs (_: lib.isDerivation) (
    pkgs.callPackage (inputs.hermes-agent + "/nix/pm-packages.nix") { patchelf = hermesPatchelf; }
  );
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
        path = "${pkgs.todoist-cli}/share/skills/todoist-cli/todoist-cli";
      }
    ]
  );

  # Browsers: the same browser-daemon MCP as Philipp's Claude and Codex sessions
  # (home-manager/devel/ai.nix). One MCP covers every node and profile
  # (`browser_use`); a throwaway browser on the node with the most room is the
  # default. It starts the Playwright MCP through browser-mcp, which tells the
  # node which agent connects (AI_AGENT=hermes below) and from which machine.
  # Authentication: browser-daemon takes the cluster secret when this user can
  # read one (it cannot) and otherwise the bd_auth token the node's dashboard
  # hands out on the mesh, so nothing is configured here.
  # Not passed: --allow-secret, --allow-passkey, --ask-human-cmd and --rbw
  # (they need an rbw vault and the user's secret agent, which this service
  # user does not have).
  browserNode = host: "https://browser.${host}.${config.domains.netbird}";
  browserMcp = pkgs.writeShellApplication {
    name = "browser-mcp";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.playwright-mcp
    ];
    text = builtins.readFile ../home-manager/devel/scripts/browser-mcp.sh;
  };
  browserDaemonMcp =
    {
      outputDir,
      extraArgs ? [ ],
    }:
    {
      command = lib.getExe' pkgs.browser-daemon "browser-daemon";
      args = [
        "mcp"
        "--url"
        (browserNode "rofl-14")
        "--playwright-cmd"
        (lib.getExe browserMcp)
        "--output-dir"
        "${config.services.hermes-agent.stateDir}/playwright-mcp/${outputDir}"
      ]
      ++ extraArgs;
      env.AI_AGENT = "hermes";
      connect_timeout = 30;
      timeout = 90;
    };
  browserMcps = {
    # The main Hermes (Signal, Matrix, ...): every tool, and the saved profiles
    # and logins the user allows agents here.
    browser-daemon = browserDaemonMcp {
      outputDir = "browser";
      extraArgs = [
        "--allow-profile"
        "*"
        "--allow-export"
        "*"
      ];
    };
    # Only for Stricknani's link imports (platform_toolsets.api_server): the same
    # tools, but throwaway browsers only. No --allow-profile and no
    # --allow-export, so an untrusted pattern page can never reach a logged-in
    # profile (Outlook, Google). Stricknani's prompt asks for a rofl-* node first.
    browser-daemon-import = browserDaemonMcp { outputDir = "browser-import"; };
  };

  # The hermes-agent module deep-merges `settings` into the mutable
  # config.yaml and never deletes a key, so MCP servers dropped from Nix stay on
  # disk. List them here and they are removed before every start. Only these
  # keys: others (bitwarden, github) may have been added by hand.
  retiredMcpServers = [
    "stricknani-importer"
    # The single GitHub server, split into github-gh-brkn-lol and github-pschmitt.
    "github"
    "playwright-browserless-fnuc"
    "playwright-browserless-rofl-13"
    "playwright-browserless-rofl-14"
    "browser-daemon-fnuc"
    "browser-daemon-rofl-13"
    "browser-daemon-rofl-14"
    "browser-daemon-rofl-15"
    "browser-daemon-rofl-16"
  ];
  hermesModel = {
    provider = "openai-codex";
    default = "gpt-6-luna";
  };
  homeAssistantMcp = {
    url = "\${MCP_HERMES_HA_URL}";
    connect_timeout = 30;
    timeout = 90;
  };
  # Restricted Hermes profiles, served by the API server under /p/<name>/v1
  # (GATEWAY_MULTIPLEX_PROFILES). The main profile keeps every tool for
  # Signal, Matrix and the API server's default route (alles). Each profile
  # here carries only the tools its caller may use, keeps its own memory, and
  # borrows the main profile's model credentials (read-only fallback to the
  # global auth.json pool). Written over on every start.
  hermesProfiles = {
    # Stricknani's link imports read untrusted pages: no built-in tools and no
    # other MCP servers, only the throwaway-browser-only browser-daemon MCP.
    stricknani = {
      model = hermesModel;
      agent.system_prompt = "";
      plugins.enabled = [ ];
      mcp_servers.browser-daemon-import = browserMcps.browser-daemon-import;
      platform_toolsets.api_server = [ "browser-daemon-import" ];
      known_plugin_toolsets.api_server = [ "homeassistant" ];
    };
    # Anika in the alles app: the house and everyday helpers, no shell, code,
    # GitHub, n8n or logged-in browsers.
    anika = {
      model = hermesModel;
      agent.system_prompt = "";
      plugins.enabled = [ "homeassistant" ];
      mcp_servers.home-assistant = homeAssistantMcp;
      platform_toolsets.api_server = [
        "web"
        "vision"
        "memory"
        "todo"
        "clarify"
        "session_search"
        "homeassistant"
        "home-assistant"
      ];
    };
  };
  hermesProfileFiles = lib.mapAttrs (
    name: settings: (pkgs.formats.yaml { }).generate "hermes-profile-${name}.yaml" settings
  ) hermesProfiles;

  hermesPruneRetiredMcp = pkgs.writeShellApplication {
    name = "hermes-prune-retired-mcp";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.yq-go
    ];
    text = ''
      config="${config.services.hermes-agent.stateDir}/.hermes/config.yaml"
      [[ -f "$config" ]] || exit 0
      yq -i 'del(.mcp_servers."home-assistant".headers)' "$config"
      # The API server's default route is the full main Hermes (alles); the
      # restricted toolsets moved to profiles (hermesProfiles).
      yq -i 'del(.platform_toolsets.api_server) | del(.known_plugin_toolsets.api_server)' "$config"
      profiles="${config.services.hermes-agent.stateDir}/.hermes/profiles"
      install -d -m 0750 "$profiles"
      ${lib.concatStrings (
        lib.mapAttrsToList (name: file: ''
          install -d -m 0750 "$profiles/${name}"
          install -m 0640 ${file} "$profiles/${name}/config.yaml"
        '') hermesProfileFiles
      )}
      for name in ${lib.escapeShellArgs retiredMcpServers}
      do
        NAME="$name" yq -i 'del(.mcp_servers[strenv(NAME)])' "$config"
      done
      chmod 0660 "$config"
    '';
  };

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
    ../modules/ha-mcp.nix
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
    secrets = {
      "n8n/mcp/token" = {
        sopsFile = config.sops.defaultSopsFile;
        mode = "0400";
      };
      "hermes/home-assistant/llat" = config.sops.mkHostSecret {
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "hermes/home-assistant/mcp-path" = config.sops.mkHostSecret { mode = "0400"; };
      "hermes/matrix/password" = config.sops.mkHostSecret {
        mode = "0400";
      };
      "hermes/matrix/recovery-key" = config.sops.mkHostSecret {
        mode = "0400";
      };
      "hermes/github/pschmitt/token" = config.sops.mkHostSecret {
        mode = "0400";
      };
      "hermes/github/gh-brkn-lol/token" = config.sops.mkHostSecret {
        mode = "0400";
      };
      "hermes/signal/account" = config.sops.mkHostSecret {
        mode = "0400";
      };
      "hermes/signal/allowed-users" = config.sops.mkHostSecret {
        mode = "0400";
      };
      "hermes/signal/group-allowed-users" = config.sops.mkHostSecret {
        mode = "0400";
      };
      "todoist/api_token" = {
        sopsFile = config.sops.defaultSopsFile;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "todoist/user_id" = {
        sopsFile = config.sops.defaultSopsFile;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "todoist/email" = {
        sopsFile = config.sops.defaultSopsFile;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "gpg/hermes/privateKey" = {
        sopsFile = rofl10SecretsFile;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "gpg/hermes/passphrase" = {
        sopsFile = rofl10SecretsFile;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "ssh/hermes-sops/privateKey" = {
        sopsFile = rofl10SecretsFile;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      # Hermes' own identity for reaching its playwright-mcp targets, kept
      # separate from ssh/nix-remote-builder/privkey so a leaked Hermes
      # credential doesn't also carry Nix distributed-build trust. Authorized
      # on rofl-13/rofl-14 for the dedicated hermes account (see
      # profiles/base/users/hermes.nix), and on fnuc for its dedicated hermes
      # account from that same shared user module.
      "ssh/hermes/privateKey" = {
        sopsFile = rofl10SecretsFile;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      # OpenAI-compatible API server (loopback only), used by Stricknani's link imports.
      "hermes/apiServer/key" = config.sops.mkHostSecret {
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
      "age/hermes-sops/keys.txt" = {
        sopsFile = rofl10SecretsFile;
        owner = config.services.hermes-agent.user;
        group = config.services.hermes-agent.group;
        mode = "0400";
      };
    };
    templates = {
      "hermes/ha-mcp-token.env" = {
        content = ''
          HOMEASSISTANT_TOKEN=${config.sops.placeholder."hermes/home-assistant/llat"}
        '';
        mode = "0400";
        restartUnits = [ "${config.virtualisation.oci-containers.backend}-ha-mcp-hermes.service" ];
      };
      "hermes/ha-mcp-path.env" = {
        content = ''
          MCP_SECRET_PATH=${config.sops.placeholder."hermes/home-assistant/mcp-path"}
        '';
        mode = "0400";
        restartUnits = [ "${config.virtualisation.oci-containers.backend}-ha-mcp-hermes.service" ];
      };
      "hermes/mcp.env" = {
        content = ''
          MCP_N8N_API_KEY=${config.sops.placeholder."n8n/mcp/token"}
          MCP_HERMES_HA_URL=http://127.0.0.1:${toString hermesHaMcpPort}${
            config.sops.placeholder."hermes/home-assistant/mcp-path"
          }
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
          GH_BRKN_LOL_TOKEN=${config.sops.placeholder."hermes/github/gh-brkn-lol/token"}
          GH_PSCHMITT_TOKEN=${config.sops.placeholder."hermes/github/pschmitt/token"}
          GH_TOKEN=${config.sops.placeholder."hermes/github/gh-brkn-lol/token"}
          IMMICH_API_KEY=${config.sops.placeholder."immich/immich-face-to-album/apiKey"}
          SIGNAL_HTTP_URL=http://127.0.0.1:${toString signalCliPort}
          API_SERVER_ENABLED=true
          API_SERVER_HOST=127.0.0.1
          API_SERVER_PORT=${toString hermesApiPort}
          API_SERVER_KEY=${config.sops.placeholder."hermes/apiServer/key"}
          SIGNAL_ACCOUNT=${config.sops.placeholder."hermes/signal/account"}
          SIGNAL_ALLOWED_USERS=${config.sops.placeholder."hermes/signal/allowed-users"}
          # Group chats: restricted to the one allowed group (see
          # hermes/signal/group-allowed-users), and only respond when
          # actually @-mentioned so it doesn't talk over every message
          # (gateway/platforms/signal.py).
          SIGNAL_GROUP_ALLOWED_USERS=${config.sops.placeholder."hermes/signal/group-allowed-users"}
          SIGNAL_REQUIRE_MENTION=true
        '';
        mode = "0400";
        restartUnits = [
          "hermes-agent.service"
          "hermes-dashboard.service"
          "signal-cli-daemon.service"
        ];
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
    ha-mcp.instances.hermes = {
      homeAssistantUrl = "https://ha.${config.domains.main}";
      tokenEnvironmentFile = config.sops.templates."hermes/ha-mcp-token.env".path;
      serverEnvironmentFile = config.sops.templates."hermes/ha-mcp-path.env".path;
      port = hermesHaMcpPort;
    };
    hermes-agent = {
      enable = true;
      package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
        version = hermesVersion;
        pmPackages = hermesPmPackages;
      };
      # Home Assistant left core for the catalog plugin. Hermes' own
      # `plugins install`/`enable` runs a uv venv sync against the read-only
      # store path and fails, so install it declaratively. Pinned to the sha
      # in hermes-agent's plugin-catalog/homeassistant.yaml.
      extraPlugins = [
        (pkgs.fetchFromGitHub {
          name = "homeassistant";
          owner = "NousResearch";
          repo = "hermes-homeassistant";
          rev = "ba30cb0cf86c52bdb5cde98974bc062e97966529"; # 2.0.1
          hash = "sha256-Pg4smvkiVpmcmUola0rziMBfq5V7UjzX8864Dem76pI=";
        })
      ];
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
        plugins.enabled = [ "homeassistant" ];
        # Signal is display_tier "low" (no message editing), which turns off
        # interim assistant messages, so replies only arrive at the end of the
        # turn. Send mid-turn text as it is produced; keep tool progress and
        # token streaming off (they would be permanent, noisy messages).
        display.platforms.signal.interim_assistant_messages = true;
        # Explicitly empty: the module merges settings into config.yaml and
        # never deletes a key that was removed here, so a former prompt would
        # otherwise linger.
        agent.system_prompt = "";
        # The API server's default route has every tool (alles). Restricted
        # callers (Stricknani's untrusted imports, Anika's alles chat) use the
        # profiles in hermesProfiles under /p/<name>/v1.
        model = hermesModel;
        tool_loop_guardrails = {
          hard_stop_enabled = true;
          hard_stop_after = {
            exact_failure = 5;
            idempotent_no_progress = 5;
          };
        };
        mcp_servers = {
          n8n-mcp = {
            url = "https://n8n.${config.domains.main}/mcp-server/http";
            headers.Authorization = "Bearer \${MCP_N8N_API_KEY}";
            connect_timeout = 30;
            timeout = 90;
          };
          home-assistant = homeAssistantMcp;
          immich = {
            command = "${pkgs.immich-mcp}/bin/ImmichMCP";
            args = [ "--stdio" ];
            env = {
              IMMICH_BASE_URL = "http://127.0.0.1:${toString config.services.immich.port}";
              IMMICH_API_KEY = "\${IMMICH_API_KEY}";
              IMMICH_TOOL_MODE = "gateway";
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
        }
        // browserMcps;
        skills.external_dirs = [ "${hermesSkills}" ];
      };
    };

    nginx.virtualHosts = {
      ${hermesHost} = {
        enableACME = false;
        useACMEHost = "wildcard.${config.domains.main}";
        forceSSL = true;
        authelia.enable = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString dashboardPort}";
          proxyWebsockets = true;
          # The module appends its recommended headers after extraConfig, which
          # would overwrite the loopback Host header Hermes requires.
          recommendedProxySettings = false;
          extraConfig = ''
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
        forceSSL = true;
        locations."/".return = "308 https://${hermesHost}$request_uri";
      };
    };

    monit.checks = {
      hermes = {
        type = "host";
        address = "127.0.0.1";
        group = "container-services";
        restartUnit = "hermes-dashboard.service";
        conditions = ''
            with timeout 180 seconds
          if failed
            port ${toString dashboardPort}
            protocol http
            request "/api/status"
            with timeout 90 seconds
          then restart
          if 5 restarts within 10 cycles then alert
        '';
      };

      hermes-signal-cli = {
        type = "host";
        address = "127.0.0.1";
        group = "container-services";
        restartUnit = "signal-cli-daemon.service";
        conditions = ''
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
    };
  };

  systemd = {
    services = {
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

      # signal-cli runs its own daemon (JSON-RPC over HTTP) that the gateway's
      # Signal adapter talks to; Hermes never calls the Signal servers
      # directly. Account registration/verification is a one-time interactive
      # step (needs a real SMS/voice code) run manually against the same data
      # dir.
      #
      # Bound to 0.0.0.0 rather than loopback-only so Home Assistant (reachable
      # only over the tailscale/netbird mesh, not roflnet) can also send
      # through this same bot account via its /api/v1/rpc JSON-RPC endpoint.
      # This is still not exposed publicly: tailscale0/nb-netbird-io are the
      # only interfaces in networking.firewall.trustedInterfaces (see
      # profiles/features/network/{tailscale,netbird}.nix), every other interface stays
      # behind the default-deny firewall.
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
          ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.signal-cli}/bin/signal-cli --scrub-log -a \"$SIGNAL_ACCOUNT\" -d ${signalCliDataDir} daemon --http 0.0.0.0:${toString signalCliPort} --receive-mode on-start'";
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
        after = [
          "${config.virtualisation.oci-containers.backend}-ha-mcp-hermes.service"
          "signal-cli-daemon.service"
        ];
        wants = [
          "${config.virtualisation.oci-containers.backend}-ha-mcp-hermes.service"
          "signal-cli-daemon.service"
        ];
        environment = {
          GNUPGHOME = gpgHome;
          SOPS_AGE_KEY_FILE = sopsAgeKeyFile;
          # Serve hermesProfiles under /p/<name>/ on the shared API server.
          GATEWAY_MULTIPLEX_PROFILES = "true";
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
          ExecStartPre = [
            (lib.getExe hermesPruneRetiredMcp)
            "${pkgs.coreutils}/bin/install -d -m 0700 ${gpgHome}"
            "${pkgs.coreutils}/bin/install -d -m 0700 ${ghConfigRoot}/gh-brkn-lol ${ghConfigRoot}/pschmitt"
            "${pkgs.gnupg}/bin/gpg --batch --yes --homedir ${gpgHome} --pinentry-mode loopback --passphrase-file ${
              config.sops.secrets."gpg/hermes/passphrase".path
            } --import ${config.sops.secrets."gpg/hermes/privateKey".path}"
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
      # Hermes' left-core migration only checks for plugins/homeassistant, but
      # the module links extraPlugins as plugins/nix-managed-<name>. Without
      # this empty marker dir (no plugin.yaml, so the loader ignores it) every
      # start tries `plugins install homeassistant`, which fails on the
      # read-only store, and posts a warning into chat.
      "d ${config.services.hermes-agent.stateDir}/.hermes/plugins/homeassistant 2770 ${config.services.hermes-agent.user} ${config.services.hermes-agent.group} - -"
      # Applies the linger setting below immediately on activation, instead of
      # waiting for the linger-users.service (wantedBy multi-user.target) to
      # run on next boot.
      "f /var/lib/systemd/linger/${config.services.hermes-agent.user}"
    ];
  };

  # Hermes' cron/Kanban workers are restart-safe by crossing `systemd-run
  # --user --scope`, which requires this account's user systemd manager (and
  # its D-Bus session) to be running. Without linger, that manager never
  # starts for a service account that never logs in, so /run/user/<uid> is
  # missing and every scheduled job fails before it is even invoked. Home
  # Manager cannot set this (it's an account property), so it must be
  # declared here. See NousResearch/hermes-agent's nix-setup docs and
  # hermes_cli/gateway.py.
  users.users.${config.services.hermes-agent.user} = {
    linger = true;
    # Its `nixos-rebuild dry-build` fetches the private flake input with the
    # system GitHub token (profiles/base/nix/secrets.nix).
    extraGroups = [ "nix-access-tokens" ];
  };

  # Require Authelia before proxying, including from the mesh. The dashboard
  # itself is loopback-only, so NGINX is its only external entry point.
  services.authelia.extraTwoFactorDomains = [ hermesHost ];

  # signal-cli-daemon above binds 0.0.0.0 so Home Assistant can reach it over
  # the mesh, relying on tailscale0/nb-netbird-io being in
  # networking.firewall.trustedInterfaces (see
  # profiles/features/network/{tailscale,netbird}.nix) -- packets arriving on those
  # interfaces are accepted before this rule is ever reached. This host's
  # firewall uses the nftables backend (services/networking/firewall-nftables.nix),
  # where extraInputRules is appended to the input-allow chain, i.e. it only
  # ever sees new connections from non-trusted interfaces. Make the deny
  # explicit here rather than relying solely on signalCliPort never ending up
  # in allowedTCPPorts.
  networking.firewall.extraInputRules = ''
    tcp dport ${toString signalCliPort} drop
  '';

  # The playwright-* MCP servers above pass -o IdentityFile explicitly, but
  # any other ssh Hermes runs on its own (e.g. from a shell tool call) has no
  # identity to fall back to otherwise -- the hermes-agent account has no
  # ~/.ssh/id_* files, so bare `ssh <host>` fails with "Permission denied
  # (publickey)" even though the key file itself is readable by this user.
  # Scope the default identity to this account via a system-wide Match block
  # instead of writing into $HOME/.ssh, since hermes-agent's home dir is
  # otherwise fully managed by the service itself.
  programs.ssh.extraConfig = ''
    Match User ${config.services.hermes-agent.user}
      IdentityFile ${config.sops.secrets."ssh/hermes/privateKey".path}
      IdentitiesOnly yes
  '';
}
