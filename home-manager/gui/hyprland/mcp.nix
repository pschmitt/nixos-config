{ pkgs, ... }:
let
  # hypruse with the compositor env discovered, so it also works from an SSH
  # session (see hosts/fnuc/hypruse-remote.nix).
  hypruseSession = pkgs.writeShellApplication {
    name = "hypruse-session";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hypruse
    ];
    text = builtins.readFile ./hypruse-session.sh;
  };
in
{
  home.packages = [ hypruseSession ];

  programs.mcp.servers.hypruse = {
    command = "${hypruseSession}/bin/hypruse-session";
  };
}
