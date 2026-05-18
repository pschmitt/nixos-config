{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:
let
  domainName =
    if osConfig != null && osConfig ? domains && osConfig.domains ? main then
      osConfig.domains.main
    else if config ? domains && config.domains ? main then
      config.domains.main
    else
      null;

  # External n8n skill set — https://github.com/czlonkowski/n8n-skills
  n8nSkillsSrc = pkgs.fetchFromGitHub {
    owner = "czlonkowski";
    repo = "n8n-skills";
    rev = "27e9d0ab92cccfc46db4f147497b173f214b69c5";
    hash = "sha256-D8wEZblUGWfXKIxw3TYXhZZ0P4C1lf71cSAVgjOpmes=";
  };

  # Generate the todoist-cli skill by importing only content.js (pure
  # constants, no side-effects) via node directly. Avoids running td itself
  # which triggers migrate-auth.js → network call → sandbox hang.
  tdSkill = pkgs.runCommand "todoist-cli-skill" { } ''
    mkdir -p "$out/todoist-cli"
    TD_SKILL_OUT="$out/todoist-cli/SKILL.md" \
    ${pkgs.nodejs}/bin/node --input-type=module << 'JSEOF'
    import { SKILL_NAME, SKILL_DESCRIPTION, SKILL_COMPATIBILITY, SKILL_CONTENT } from '${pkgs.todoist-cli}/lib/node_modules/@doist/todoist-cli/dist/lib/skills/content.js';
    import { readFileSync, writeFileSync } from 'node:fs';
    const pkg = JSON.parse(readFileSync('${pkgs.todoist-cli}/lib/node_modules/@doist/todoist-cli/package.json', 'utf-8'));
    const frontmatter = '---\n'
      + 'name: ' + SKILL_NAME + '\n'
      + 'description: ' + JSON.stringify(SKILL_DESCRIPTION) + '\n'
      + 'compatibility: ' + JSON.stringify(SKILL_COMPATIBILITY) + '\n'
      + 'license: ' + pkg.license + '\n'
      + 'metadata:\n'
      + '  author: Doist\n'
      + '  version: ' + JSON.stringify(pkg.version) + '\n'
      + '---\n\n';
    writeFileSync(process.env.TD_SKILL_OUT, frontmatter + SKILL_CONTENT, 'utf-8');
    JSEOF
  '';

  # Merge local skills with the upstream n8n skill set so all AI tools get both.
  # toString coerces the derivation to its store-path string, which the skills
  # option type accepts (it rejects raw derivations as it matches the attrsOf branch).
  allSkills = toString (
    pkgs.symlinkJoin {
      name = "ai-skills";
      paths = [
        ./skills
        "${n8nSkillsSrc}/skills"
        tdSkill
      ];
    }
  );

  n8nMcpTokenFile = config.sops.secrets."n8n/mcp/token".path;
  homeAssistantMcpTokenFile = config.sops.secrets."home-assistant/mcp/token".path;
  homeAssistantMcpUrl = "https://ha.${domainName}/api/mcp";

  wrapAiToolWithMcpEnv =
    {
      package,
      binary,
    }:
    pkgs.symlinkJoin {
      name = "${lib.getName package}-with-mcp-env";
      paths = [ package ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram "$out/bin/${binary}" \
          --set-default N8N_MCP_TOKEN_FILE ${lib.escapeShellArg n8nMcpTokenFile} \
          --set-default HASS_TOKEN_FILE ${lib.escapeShellArg homeAssistantMcpTokenFile} \
          --run 'if [[ -r "$N8N_MCP_TOKEN_FILE" ]]; then export N8N_MCP_TOKEN="$(<"$N8N_MCP_TOKEN_FILE")"; fi' \
          --run 'if [[ -r "$HASS_TOKEN_FILE" ]]; then export HASS_TOKEN="$(<"$HASS_TOKEN_FILE")"; fi'
      '';
      inherit (package) meta;
    };
in
{
  assertions = [
    {
      assertion = domainName != null;
      message = ''
        Unable to determine the main domain for AI MCP configuration.
        Define `domains.main` in the standalone Home Manager host module or run this config under NixOS-backed Home Manager.
      '';
    }
  ];

  sops = {
    secrets = {
      "mistral-vibe/env" = {
        mode = "0600";
        sopsFile = ../../secrets/shared.sops.yaml;
      };
      "n8n/mcp/token" = {
        mode = "0600";
        sopsFile = ../../secrets/shared.sops.yaml;
      };
      "home-assistant/mcp/token" = {
        mode = "0600";
        sopsFile = ../../secrets/shared.sops.yaml;
      };
    };
  };

  programs.mcp = {
    enable = true;
    servers =
      lib.optionalAttrs (domainName != null) {
        n8n-mcp = {
          url = "https://n8n.${domainName}/mcp-server/http";
          headers = {
            Authorization = "Bearer {env:N8N_MCP_TOKEN}";
          };
        };
        home-assistant = {
          url = homeAssistantMcpUrl;
          headers = {
            Authorization = "Bearer {env:HASS_TOKEN}";
          };
        };
      }
      // {
        obsidian = {
          command = "${pkgs.mcp-server-filesystem}/bin/mcp-server-filesystem";
          args = [ "/home/pschmitt/Documents/notes" ];
        };
      };
  };

  programs = {
    claude-code = {
      enable = true;
      package = wrapAiToolWithMcpEnv {
        package = pkgs.llm-agents.claude-code;
        binary = "claude";
      };
      skills = allSkills;
      enableMcpIntegration = false;
      # MCP servers are written via home.activation (see below) because
      # {env:VAR} substitution does not work in plugin-dir .mcp.json files.
      settings = {
        skipDangerousModePermissionPrompt = true;
        theme = "dark";
      };
      rules = {
        code-style = ./CODESTYLE.md;
      };
    };

    codex = {
      enable = true;
      package = wrapAiToolWithMcpEnv {
        package = pkgs.llm-agents.codex;
        binary = "codex";
      };
      context = ./CODESTYLE.md;
      skills = allSkills;
      enableMcpIntegration = true;
    };

    gemini-cli = {
      enable = true;
      package = wrapAiToolWithMcpEnv {
        package = pkgs.llm-agents.gemini-cli;
        binary = "gemini";
      };
      skills = allSkills;
      # Gemini requires httpUrl (not url+type) and ${VAR} env syntax.
      # programs.mcp produces the wrong schema, so wire MCP directly here.
      enableMcpIntegration = false;
      settings = {
        general = {
          preferredEditor = "nvim";
          previewFeatures = true;
          vimMode = false;

          sessionRetention = {
            enabled = true;
            maxAge = "30d";
            maxCount = 50;
          };
        };

        security = {
          auth = {
            selectedType = "oauth-personal";
          };
        };

        context = {
          loadMemoryFromIncludeDirectories = true;
          fileName = [
            "AGENTS.md"
            "CLAUDE.md"
            "CONTEXT.md"
            "CODESTYLE.md"
            "GEMINI.md"
          ];
        };

        tools.shell.showColor = true;

        mcpServers =
          lib.optionalAttrs (domainName != null) {
            home-assistant = {
              httpUrl = homeAssistantMcpUrl;
              headers.Authorization = "Bearer \${HASS_TOKEN}";
            };
            n8n-mcp = {
              httpUrl = "https://n8n.${domainName}/mcp-server/http";
              headers.Authorization = "Bearer \${N8N_MCP_TOKEN}";
            };
          }
          // {
            obsidian = {
              command = "${pkgs.mcp-server-filesystem}/bin/mcp-server-filesystem";
              args = [ "/home/pschmitt/Documents/notes" ];
            };
          };
      };
    };

    opencode = {
      enable = true;
      package = wrapAiToolWithMcpEnv {
        package = pkgs.llm-agents.opencode;
        binary = "opencode";
      };
      skills = allSkills;
      context = builtins.readFile ./CODESTYLE.md;
      web.enable = false;
      enableMcpIntegration = true;
    };

    github-copilot-cli = {
      enable = true;
      package = wrapAiToolWithMcpEnv {
        package = pkgs.llm-agents.copilot-cli;
        binary = "copilot";
      };
      skills = allSkills;
      context = ./CODESTYLE.md;
      enableMcpIntegration = true;
    };
  };

  # FIXME vibe-cli is broken as of 2026-02-25
  # Create ~/.config/vibe directory and .env file
  # xdg.configFile =
  #   let
  #     tomlFormat = pkgs.formats.toml { };
  #     vibeUpstreamCliPrompt = builtins.readFile "${pkgs.master.mistral-vibe.src}/vibe/core/prompts/cli.md";
  #     vibeCustomPromptId = "cli_codestyle";
  #     vibeCustomPrompt = vibeUpstreamCliPrompt + "\n\n" + builtins.readFile ./CODESTYLE.md;
  #   in
  #   {
  #     "vibe/.env".source =
  #       config.lib.file.mkOutOfStoreSymlink
  #         config.sops.secrets."mistral-vibe/env".path;
  #
  #     "vibe/config.toml".source = tomlFormat.generate "config.toml" {
  #       system_prompt_id = vibeCustomPromptId;
  #     };
  #
  #     "vibe/prompts/${vibeCustomPromptId}.md".text = vibeCustomPrompt;
  #   };

  home = {
    # Write MCP servers directly to ~/.claude.json user-scope so that Claude
    # Code can authenticate with real token values. {env:VAR} substitution does
    # not work in plugin-dir .mcp.json health checks, causing servers to be
    # marked as needing OAuth. home.activation reads the sops-decrypted tokens
    # at switch time and embeds the actual values in the mutable config file.
    activation.claudeCodeMcpServers = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        obsidianJson = builtins.toJSON {
          type = "stdio";
          command = "${pkgs.mcp-server-filesystem}/bin/mcp-server-filesystem";
          args = [ "/home/pschmitt/Documents/notes" ];
        };
        haUrl = lib.optionalString (domainName != null) homeAssistantMcpUrl;
        n8nUrl = lib.optionalString (domainName != null) "https://n8n.${domainName}/mcp-server/http";
      in
      ''
        CLAUDE_JSON="$HOME/.claude.json"

        N8N_TOKEN=""
        HASS_TOKEN=""
        if [[ -r "${n8nMcpTokenFile}" ]]; then
          N8N_TOKEN="$(<"${n8nMcpTokenFile}")"
        fi
        if [[ -r "${homeAssistantMcpTokenFile}" ]]; then
          HASS_TOKEN="$(<"${homeAssistantMcpTokenFile}")"
        fi

        MCP_SERVERS=$(${pkgs.jq}/bin/jq -n \
          --argjson obsidian ${lib.escapeShellArg obsidianJson} \
          --arg ha_url ${lib.escapeShellArg haUrl} \
          --arg n8n_url ${lib.escapeShellArg n8nUrl} \
          --arg n8n_token "$N8N_TOKEN" \
          --arg hass_token "$HASS_TOKEN" \
          '{
            "obsidian": $obsidian,
            "home-assistant": {
              "type": "http",
              "url": $ha_url,
              "headers": {"Authorization": ("Bearer " + $hass_token)}
            },
            "n8n-mcp": {
              "type": "http",
              "url": $n8n_url,
              "headers": {"Authorization": ("Bearer " + $n8n_token)}
            }
          }')

        if [[ -f "$CLAUDE_JSON" ]]; then
          ${pkgs.jq}/bin/jq --argjson mcp "$MCP_SERVERS" '.mcpServers = $mcp' \
            "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" \
            && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
        else
          ${pkgs.jq}/bin/jq -n --argjson mcp "$MCP_SERVERS" '{mcpServers: $mcp}' \
            > "$CLAUDE_JSON"
        fi
      ''
    );

    # Write MCP servers to Codex's actual config at ~/.config/codex/config.toml.
    # The HM codex module writes to ~/.codex/config.yaml (non-XDG path) because
    # the llm-agents codex package has no version attribute (lib.getVersion
    # returns ""), so isTomlConfig=false and useXdgDirectories=false. In a fresh
    # shell, Codex uses XDG_CONFIG_HOME/codex (~/.config/codex), ignoring the HM
    # config. pkgs.writeText keeps the TOML template at correct indentation
    # regardless of nixfmt; sed substitutes token placeholders at runtime.
    activation.codexMcpServers = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      let
        haUrl = lib.optionalString (domainName != null) homeAssistantMcpUrl;
        n8nUrl = lib.optionalString (domainName != null) "https://n8n.${domainName}/mcp-server/http";
        obsidianCmd = "${pkgs.mcp-server-filesystem}/bin/mcp-server-filesystem";
        obsidianArg = "/home/pschmitt/Documents/notes";
        mcpTomlTemplate = pkgs.writeText "codex-mcp-servers.toml" ''
          [mcp_servers.home-assistant]
          enabled = true
          url = "${haUrl}"

          [mcp_servers.home-assistant.http_headers]
          Authorization = "Bearer __HASS_TOKEN__"

          [mcp_servers.n8n-mcp]
          enabled = true
          url = "${n8nUrl}"

          [mcp_servers.n8n-mcp.http_headers]
          Authorization = "Bearer __N8N_TOKEN__"

          [mcp_servers.obsidian]
          enabled = true
          command = "${obsidianCmd}"
          args = ["${obsidianArg}"]
        '';
      in
      ''
        CODEX_TOML="${"\${CODEX_HOME:-$HOME/.config/codex}"}/config.toml"
        mkdir -p "$(dirname "$CODEX_TOML")"
        [[ -f "$CODEX_TOML" ]] || touch "$CODEX_TOML"

        N8N_TOKEN=""
        HASS_TOKEN=""
        if [[ -r "${n8nMcpTokenFile}" ]]; then
          N8N_TOKEN="$(<"${n8nMcpTokenFile}")"
        fi
        if [[ -r "${homeAssistantMcpTokenFile}" ]]; then
          HASS_TOKEN="$(<"${homeAssistantMcpTokenFile}")"
        fi

        ${pkgs.gawk}/bin/awk '
          /^\[mcp_servers/ { skip = 1 }
          /^\[/ && !/^\[mcp_servers/ { skip = 0 }
          !skip { print }
        ' "$CODEX_TOML" > "$CODEX_TOML.tmp" && mv "$CODEX_TOML.tmp" "$CODEX_TOML"

        ${pkgs.gnused}/bin/sed \
          -e "s|__HASS_TOKEN__|$HASS_TOKEN|" \
          -e "s|__N8N_TOKEN__|$N8N_TOKEN|" \
          "${mcpTomlTemplate}" >> "$CODEX_TOML"
      ''
    );

    packages = with pkgs.master; [
      # vscode forks
      antigravity
      # code-cursor

      # cli
      # cursor-cli
      # kilocode-cli

      # FIXME vibe-cli is broken as of 2026-02-25
      # (pkgs.writeShellScriptBin "vibe" ''
      #   export VIBE_HOME="''${VIBE_HOME:-${config.xdg.configHome}/vibe}"
      #
      #   exec ${mistral-vibe}/bin/vibe "$@"
      # '')
    ];
  };
}
