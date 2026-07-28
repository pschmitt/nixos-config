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
  dashboardPort = 9119;
  autheliaConfig = import ./authelia-nginx-config.nix { inherit config; };

  # Hermes treats external skill directories as read-only and discovers the
  # agentskills.io-compatible SKILL.md files from this Nix store path.
  hermesSkills = pkgs.symlinkJoin {
    name = "hermes-skills";
    paths = [ ./hermes/skills ];
  };
in
{
  imports = [
    inputs.hermes-agent.nixosModules.default
  ];

  sops = {
    # The existing MCP tokens stay encrypted at rest and are exposed to the
    # gateway only through a root-owned systemd environment file.
    secrets = {
      "n8n/mcp/token" = {
        sopsFile = ../secrets/shared.sops.yaml;
        mode = "0400";
      };
      "home-assistant/mcp/token" = {
        sopsFile = ../secrets/shared.sops.yaml;
        mode = "0400";
      };
      "hermes/home-assistant/llat" = config.custom.mkSecret {
        mode = "0400";
      };
      "hermes/matrix/password" = config.custom.mkSecret {
        mode = "0400";
      };
      "hermes/matrix/recovery-key" = config.custom.mkSecret {
        mode = "0400";
      };
    };
    templates."hermes/mcp.env" = {
      content = ''
        MCP_N8N_API_KEY=${config.sops.placeholder."n8n/mcp/token"}
        MCP_HOME_ASSISTANT_API_KEY=${config.sops.placeholder."home-assistant/mcp/token"}
        HASS_URL=https://ha.${config.domains.main}
        HASS_TOKEN=${config.sops.placeholder."hermes/home-assistant/llat"}
        MATRIX_HOMESERVER=https://matrix-client.matrix.org
        MATRIX_PASSWORD=${config.sops.placeholder."hermes/matrix/password"}
        MATRIX_USER_ID=@hermes-brkn:matrix.org
        MATRIX_ALLOWED_USERS=@pschmitt:one.ems.host
        MATRIX_E2EE_MODE=required
        MATRIX_DEVICE_ID=HERMESROFL10
        MATRIX_RECOVERY_KEY=${config.sops.placeholder."hermes/matrix/recovery-key"}
      '';
      mode = "0400";
      restartUnits = [
        "hermes-agent.service"
        "hermes-dashboard.service"
      ];
    };
  };

  services = {
    hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      stateDir = "/srv/hermes";
      workingDirectory = "/srv/hermes/workspace";
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
    '';
  };

  # The upstream module runs the gateway natively. Its dashboard is a separate
  # process, bound to loopback and protected by a two-factor Authelia policy.
  systemd.services.hermes-dashboard = {
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

  systemd.services.hermes-agent.serviceConfig.EnvironmentFile = [
    config.sops.templates."hermes/mcp.env".path
  ];

  # Require Authelia before proxying, including from the mesh. The dashboard
  # itself is loopback-only, so NGINX is its only external entry point.
  custom.authelia.extraTwoFactorDomains = [ hermesHost ];
}
