{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.mainUser.username;

  hypruseHub = pkgs.writers.writePython3Bin "hypruse-hub" {
    libraries = [ pkgs.python3Packages.mcp ];
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ./scripts/hypruse-hub.py);
in
{
  # One hypruse MCP for all laptops: tools take a `host` argument and the
  # hub opens SSH sessions to that host's hypruse-session on demand (see
  # home-manager/gui/hyprland/mcp.nix).
  home-manager.users.${user}.programs.mcp.servers.hypruse = {
    command = lib.getExe hypruseHub;
    args = [
      "--ssh"
      (lib.getExe' pkgs.openssh "ssh")
      "--remote-cmd"
      "/etc/profiles/per-user/${user}/bin/hypruse-session"
      "ge2"
      "gk4"
    ];
  };
}
