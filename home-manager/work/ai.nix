{
  config,
  pkgs,
  ...
}:
let
  claudeWorkSettings = (pkgs.formats.json { }).generate "claude-work-settings.json" {
    statusLine = config.programs.claude-code.settings.statusLine;
    inherit (config.programs.claude-code.settings) env teammateDefaultModel;
  };

  claudeWork = pkgs.writeShellApplication {
    name = "claude-work";

    text = ''
      : "''${HOME:?HOME must be set}"

      export CLAUDE_CONFIG_DIR="''${XDG_CONFIG_HOME:-$HOME/.config}/claude-work"
      export ANTHROPIC_CONFIG_DIR="''${ANTHROPIC_CONFIG_DIR:-$CLAUDE_CONFIG_DIR}"
      export CLAUDE_CODE_SUBAGENT_MODEL="sonnet"
      export CLAUDE_CODE_SUBAGENT_MODEL_FORCE="1"

      exec ${config.programs.claude-code.finalPackage}/bin/claude \
        --settings "${claudeWorkSettings}" \
        "$@"
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
    # delivered to the default XDG Claude config dir as a generated
    # "claude-code-home-manager" personal plugin. Symlink that same plugin
    # in here so claude-work gets the same MCP servers.
    ".config/claude-work/skills/claude-code-home-manager".source =
      config.lib.file.mkOutOfStoreSymlink "${config.programs.claude-code.configDir}/skills/claude-code-home-manager";
  };

  home.packages = [ claudeWork ];
}
