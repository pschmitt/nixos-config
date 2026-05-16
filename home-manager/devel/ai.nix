{
  config,
  osConfig,
  lib,
  pkgs,
  ...
}:
let
  # External n8n skill set — https://github.com/czlonkowski/n8n-skills
  n8nSkillsSrc = pkgs.fetchFromGitHub {
    owner = "czlonkowski";
    repo = "n8n-skills";
    rev = "27e9d0ab92cccfc46db4f147497b173f214b69c5";
    hash = "sha256-D8wEZblUGWfXKIxw3TYXhZZ0P4C1lf71cSAVgjOpmes=";
  };

  # Merge local skills with the upstream n8n skill set so all AI tools get both.
  # toString coerces the derivation to its store-path string, which the skills
  # option type accepts (it rejects raw derivations as it matches the attrsOf branch).
  allSkills = toString (
    pkgs.symlinkJoin {
      name = "ai-skills";
      paths = [
        ./skills
        "${n8nSkillsSrc}/skills"
      ];
    }
  );

  n8nMcpTokenFile = config.sops.secrets."n8n/mcp/token".path;

  wrapAiToolWithN8nMcp =
    {
      package,
      binary,
    }:
    pkgs.symlinkJoin {
      name = "${lib.getName package}-with-n8n-mcp";
      paths = [ package ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram "$out/bin/${binary}" \
          --set-default N8N_MCP_TOKEN_FILE ${lib.escapeShellArg n8nMcpTokenFile} \
          --run 'if [[ -r "$N8N_MCP_TOKEN_FILE" ]]; then export N8N_MCP_TOKEN="$(<"$N8N_MCP_TOKEN_FILE")"; fi'
      '';
      inherit (package) meta;
    };
in
{
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
    };
  };

  programs.mcp = {
    enable = true;
    servers = {
      n8n-mcp = {
        url = "https://n8n.${osConfig.domain.main}/mcp-server/http";
        headers = {
          Authorization = "Bearer {env:N8N_MCP_TOKEN}";
        };
      };
    };
  };

  programs = {
    claude-code = {
      enable = true;
      package = wrapAiToolWithN8nMcp {
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
      package = wrapAiToolWithN8nMcp {
        package = pkgs.llm-agents.codex;
        binary = "codex";
      };
      context = ./CODESTYLE.md;
      skills = allSkills;
      enableMcpIntegration = true;
    };

    gemini-cli = {
      enable = true;
      package = wrapAiToolWithN8nMcp {
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
      package = wrapAiToolWithN8nMcp {
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
      package = wrapAiToolWithN8nMcp {
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
