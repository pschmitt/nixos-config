{ pkgs, ... }:
{
  # GUI-only browser automation MCP servers. Kept out of home-manager/devel/ai.nix
  # (imported on every host, including headless servers like fnuc) since these
  # need a local browser to drive.
  programs.mcp.servers = {
    firefox-devtools = {
      command = "${pkgs.firefox-devtools-mcp}/bin/firefox-devtools-mcp";
      args = [
        "--firefox-path"
        "${pkgs.firefox}/bin/firefox"
      ];
    };

    playwright = {
      command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
      args = [
        "--headless"
        "--isolated"
      ];
    };
  };
}
