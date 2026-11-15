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
}
