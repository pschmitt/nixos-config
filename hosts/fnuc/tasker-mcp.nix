{ config, pkgs, ... }:
let
  taskerMcp = pkgs.writeShellApplication {
    name = "tasker-mcp-local";
    runtimeInputs = [
      pkgs.android-tools
      pkgs.tasker-mcp
    ];
    text = builtins.readFile ./scripts/tasker-mcp.sh;
  };
in
{
  programs.mcp.servers.tasker = {
    command = "${taskerMcp}/bin/tasker-mcp-local";
    env.TASKER_MCP_CONFIG_DIR = "${config.xdg.configHome}/tasker-mcp";
  };

  # Second phone (Zenfone 10). adb-serial and token live in the config dir.
  programs.mcp.servers.tasker-zf10 = {
    command = "${taskerMcp}/bin/tasker-mcp-local";
    env = {
      TASKER_MCP_CONFIG_DIR = "${config.xdg.configHome}/tasker-mcp-zf10";
      TASKER_MCP_HOME = "${config.xdg.stateHome}/tasker-mcp-zf10";
      # Own local adb forward port: tasker-mcp would otherwise use 1821 for both phones.
      TASKER_FORWARD_PORT = "18211";
    };
  };
}
