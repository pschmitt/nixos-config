{
  config,
  pkgs,
  ...
}:
let
  claudeWork = pkgs.writeShellApplication {
    name = "claude-work";

    text = ''
      : "''${HOME:?HOME must be set}"

      export CLAUDE_CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-''${XDG_CONFIG_HOME:-$HOME/.config}/claude-work}"
      export ANTHROPIC_CONFIG_DIR="''${ANTHROPIC_CONFIG_DIR:-$CLAUDE_CONFIG_DIR}"

      exec ${config.programs.claude-code.finalPackage}/bin/claude "$@"
    '';
  };
in
{
  home.file = {
    ".config/claude-work/rules/context.md".source = ../devel/CONTEXT.md;
    ".config/claude-work/skills" = {
      source = config.programs.claude-code.skills;
      recursive = true;
    };
  };

  home.packages = [ claudeWork ];
}
