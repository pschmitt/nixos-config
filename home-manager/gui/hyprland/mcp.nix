{ pkgs, ... }:
{
  programs.mcp.servers.hypruse = {
    command = "${pkgs.hypruse}/bin/hypruse";
    env = {
      HYPRUSE_AUTH_GUARD = "strict";
      HYPRUSE_STRICT = "1";
    };
  };
}
