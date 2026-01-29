{ pkgs, ... }:
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
          vimMode = true;
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
  };

  home.packages = with pkgs.master; [
    # vscode forks
    antigravity
    code-cursor

    # cli
    cursor-cli
    github-copilot-cli
  ];
}
