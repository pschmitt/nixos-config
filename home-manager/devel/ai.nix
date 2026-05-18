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
      enableMcpIntegration = true;
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
      enableMcpIntegration = true;
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

  home.packages = with pkgs.master; [
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
}
