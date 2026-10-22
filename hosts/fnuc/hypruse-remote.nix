{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.mainUser.username;
  # Same module as the laptops' local hypruse MCP: it finds the running
  # Hyprland session by itself, so a plain SSH command is enough.
  remoteCommand = "/etc/profiles/per-user/${user}/bin/hypruse-session";

  laptops = [
    "ge2"
    "gk4"
  ];
in
{
  home-manager.users.${user}.programs.mcp.servers = lib.genAttrs' laptops (host: {
    name = "hypruse-${host}";
    value = {
      command = lib.getExe' pkgs.openssh "ssh";
      args = [
        "-q"
        "-T"
        "-o"
        "BatchMode=yes"
        "-o"
        "ServerAliveInterval=30"
        host
        remoteCommand
      ];
    };
  });
}
