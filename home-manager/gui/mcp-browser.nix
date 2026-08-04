{ pkgs, ... }:
{
  # GUI-only browser automation MCP servers. Kept out of home-manager/devel/ai.nix
  # (imported on every host, including headless servers like fnuc) since these
  # need a local browser to drive.
  programs.mcp.servers = {
    browsermcp = {
      command = "${pkgs.browsermcp}/bin/mcp-server-browsermcp";
    };

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
        "--browser"
        "firefox"
      ];
    };
  };

  # Browser MCP (browsermcp.io) is Chrome-only: it drives the browser through
  # this extension rather than launching its own instance.
  custom.desktop.browser.chromium.extensions = [
    { id = "bjfgambnhccakkhmkepdoekmckoijdlc"; }
  ];
}
