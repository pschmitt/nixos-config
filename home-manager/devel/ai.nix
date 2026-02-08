{
  pkgs,
  config,
  ...
}:
let
  tomlFormat = pkgs.formats.toml { };
  vibeUpstreamCliPrompt = builtins.readFile "${pkgs.master.mistral-vibe.src}/vibe/core/prompts/cli.md";
  vibeCustomPromptId = "cli_codestyle";
  vibeCustomPrompt = vibeUpstreamCliPrompt + "\n\n" + builtins.readFile ./CODESTYLE.md;
in
{

  programs = {
    claude-code = {
      enable = true;
      package = pkgs.master.codex;
      enableMcpIntegration = true;
    };

    codex = {
      enable = true;
      package = pkgs.master.codex;
      custom-instructions = builtins.readFile ./CODESTYLE.md;
    };

    gemini-cli = {
      enable = true;
      package = pkgs.master.gemini-cli;
      settings = {
        general = {
          preferredEditor = "nvim";
          previewFeatures = true;
          vimMode = false;
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
      package = pkgs.master.opencode;
      enableMcpIntegration = true;
      rules = builtins.readFile ./CODESTYLE.md;
      web.enable = false;
    };
  };

  sops.secrets = {
    "mistral-vibe/env" = {
      mode = "0600";
    };
  };

  # Create ~/.config/vibe directory and .env file
  xdg.configFile = {
    "vibe/.env".source =
      config.lib.file.mkOutOfStoreSymlink
        config.sops.secrets."mistral-vibe/env".path;

    "vibe/config.toml".source = tomlFormat.generate "config.toml" {
      system_prompt_id = vibeCustomPromptId;
    };

    "vibe/prompts/${vibeCustomPromptId}.md".text = vibeCustomPrompt;
  };

  home.packages = with pkgs.master; [
    # vscode forks
    antigravity
    code-cursor

    # cli
    cursor-cli
    github-copilot-cli
    (pkgs.writeShellScriptBin "vibe" ''
      export VIBE_HOME="''${VIBE_HOME:-${config.xdg.configHome}/vibe}"

      exec ${mistral-vibe}/bin/vibe "$@"
    '')
  ];
}
