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
      custom-instructions = ''
        ## Shell code

        The following applies to bash, sh and zsh.

        ### Style and Structure
        - **Indentation**: Use two spaces per indentation level. Do not mix tabs and spaces.
        - **Control structures**: Place keywords on separate lines—e.g. write `if condition` followed by `then` on the next line, and do
          the same for `elif`, `else`, `for`, `while`, and `until` blocks. Never combine multiple statements on one line with semicolons
          inside conditionals or loops.
        - **Functions**: Define functions with the `name() { ... }` form. Avoid anonymous functions and keep function bodies focused on
          a single responsibility.
      '';
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
            "GEMINI.md"
          ];
        };
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
