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

  mcpHttpProxy =
    name:
    {
      url,
      tokenFile,
    }:
    pkgs.writeShellApplication {
      name = "${name}-mcp";
      runtimeInputs = [ pkgs.mcp-proxy ];
      text = ''
        token_file=${lib.escapeShellArg tokenFile}

        if [[ ! -r "$token_file" ]]; then
          printf 'MCP token file is not readable: %s\n' "$token_file" >&2
          exit 1
        fi

        API_ACCESS_TOKEN="$(<"$token_file")"
        export API_ACCESS_TOKEN

        exec mcp-proxy \
          "$@" \
          --transport streamablehttp \
          --verify-ssl ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
          ${lib.escapeShellArg url}
      '';
    };

  withEnv =
    pkg:
    pkgs.symlinkJoin {
      name = "${pkg.name}-with-env";
      paths = [ pkg ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        for bin in $out/bin/*; do
          wrapProgram "$bin" \
            --run 'set -a; [ -f "${config.sops.templates."gmail-mcp.env".path}" ] && source "${
              config.sops.templates."gmail-mcp.env".path
            }"; set +a'
        done
      '';
    };

  mcpServers =
    lib.optionalAttrs (domainName != null) {
      n8n-mcp = {
        command = "${
          mcpHttpProxy "n8n" {
            url = "https://n8n.${domainName}/mcp-server/http";
            tokenFile = n8nMcpTokenFile;
          }
        }/bin/n8n-mcp";
      };
      home-assistant = {
        command = "${
          mcpHttpProxy "home-assistant" {
            url = homeAssistantMcpUrl;
            tokenFile = homeAssistantMcpTokenFile;
          }
        }/bin/home-assistant-mcp";
      };
    }
    // {
      obsidian = {
        command = "${pkgs.mcp-server-filesystem}/bin/mcp-server-filesystem";
        args = [ "/home/pschmitt/Documents/notes" ];
      };
      gmail = {
        url = "https://gmailmcp.googleapis.com/mcp/v1";
        oauth = {
          enabled = true;
          clientId = "\${GMAIL_MCP_CLIENT_ID}";
          clientSecret = "\${GMAIL_MCP_CLIENT_SECRET}";
          scopes = [
            "https://www.googleapis.com/auth/gmail.readonly"
            "https://www.googleapis.com/auth/gmail.compose"
            "https://www.googleapis.com/auth/gmail.modify"
          ];
        };
      };
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
    templates."gmail-mcp.env".content = ''
      GMAIL_MCP_CLIENT_ID="${config.sops.placeholder."gmail/mcp/client_id"}"
      GMAIL_MCP_CLIENT_SECRET="${config.sops.placeholder."gmail/mcp/client_secret"}"
    '';
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
      "gmail/mcp/client_id" = {
        mode = "0600";
        sopsFile = ../../secrets/shared.sops.yaml;
      };
      "gmail/mcp/client_secret" = {
        mode = "0600";
        sopsFile = ../../secrets/shared.sops.yaml;
      };
    };
  };

  programs.mcp = {
    enable = true;
    servers = mcpServers;
  };

  programs = {
    claude-code = {
      enable = true;
      package = withEnv pkgs.llm-agents.claude-code;
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
      package = withEnv pkgs.llm-agents.codex;
      context = ./CODESTYLE.md;
      skills = allSkills;
      enableMcpIntegration = true;
      settings = {
        model = "gpt-5.4";
        model_reasoning_effort = "medium";
      };
    };

    gemini-cli = {
      enable = true;
      package = withEnv pkgs.llm-agents.gemini-cli;
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
      package = withEnv pkgs.llm-agents.opencode;
      skills = allSkills;
      context = builtins.readFile ./CODESTYLE.md;
      web.enable = false;
      enableMcpIntegration = true;
    };

    github-copilot-cli = {
      enable = true;
      package = withEnv pkgs.llm-agents.copilot-cli;
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
