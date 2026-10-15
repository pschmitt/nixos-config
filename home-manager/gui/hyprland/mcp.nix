{ pkgs, ... }:
{
  programs.mcp.servers.hypruse = {
    command = "${pkgs.hypruse}/bin/hypruse";
    args = [ "mcp" ];
    env = {
      HYPRUSE_AUTH_GUARD = "strict";
      HYPRUSE_STRICT = "1";
    };
  };
}
