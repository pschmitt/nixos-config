{
  pkgs,
  inputs,
  ...
}:
let
  codeCursor = pkgs.master.code-cursor.overrideAttrs (_old: {
    src = pkgs.fetchurl {
      url = "https://downloads.cursor.com/production/475871d112608994deb2e3065dfb7c6b0baa0c54/linux/x64/Cursor-3.0.16-x86_64.AppImage";
      hash = "sha256-dN8tFSppIpO/P0Thst5uaNzlmfWZDh0Y81Lx1BuSYt0=";
    };
  });
in
{

  programs = {
    claude-code = {
      enable = true;
      package = pkgs.master.claude-code;
      enableMcpIntegration = true;
    };

    codex = {
      enable = true;
      package = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
    codeCursor

    # cli
    cursor-cli
    github-copilot-cli
    # kilocode-cli

    # FIXME vibe-cli is broken as of 2026-02-25
    # (pkgs.writeShellScriptBin "vibe" ''
    #   export VIBE_HOME="''${VIBE_HOME:-${config.xdg.configHome}/vibe}"
    #
    #   exec ${mistral-vibe}/bin/vibe "$@"
    # '')
  ];
}
