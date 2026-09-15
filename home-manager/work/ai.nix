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
    ".config/claude-work/keybindings.json".source = ../devel/claude-keybindings.json;
    ".config/claude-work/skills" = {
      source = config.programs.claude-code.skills;
      recursive = true;
    };
    # `claude-work` runs with CLAUDE_CONFIG_DIR pointed at a separate
    # directory (see claudeWork above), so it never sees the MCP servers
    # from programs.mcp.servers (home-manager/devel/ai.nix): those are
    # delivered to the default ~/.claude config dir as a generated
    # "claude-code-home-manager" personal plugin. Symlink that same plugin
    # in here so claude-work gets the same MCP servers.
    ".config/claude-work/skills/claude-code-home-manager".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.claude/skills/claude-code-home-manager";
  };

  home.packages = [ claudeWork ];
}
