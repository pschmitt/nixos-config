{
  pkgs,
  ...
}:
{

  programs = {
    claude-code = {
      enable = true;
      package = pkgs.llm-agents.claude-code;
      skills = ./skills;
      enableMcpIntegration = true;
      rules = {
        code-style = ./CODESTYLE.md;
      };
    };

    codex = {
      enable = true;
      package = pkgs.llm-agents.codex;
      context = ./CODESTYLE.md;
      skills = ./skills;
    };

    gemini-cli = {
      enable = true;
      package = pkgs.llm-agents.gemini-cli;
      skills = ./skills;
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
      package = pkgs.llm-agents.opencode;
      skills = ./skills;
      enableMcpIntegration = true;
      context = builtins.readFile ./CODESTYLE.md;
      web.enable = false;
    };

    github-copilot-cli = {
      enable = true;
      package = pkgs.llm-agents.copilot-cli;
      skills = ./skills;
      enableMcpIntegration = true;
      context = ./CODESTYLE.md;
    };
  };

  sops.secrets = {
    "mistral-vibe/env" = {
      mode = "0600";
      sopsFile = ../../secrets/shared.sops.yaml;
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
