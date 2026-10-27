{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.mainUser.username;

  # The hub uses the MCP 1.x lowlevel decorators (and hypruse 0.13 needs 1.x
  # too), so build it from the stable set while unstable ships MCP 2.x.
  hypruseHub = pkgs.stable.writers.writePython3Bin "hypruse-hub" {
    libraries = [ pkgs.stable.python3Packages.mcp ];
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
