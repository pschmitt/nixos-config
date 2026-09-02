{ inputs, ... }:
{
  # Module import only: `programs.dank-material-shell.enable` is opt-in per
  # host (see hosts/gk4/default.nix), same as quickshell-bar's Waybar
  # alternative status.
  imports = [
    inputs.dankMaterialShell.homeModules.dank-material-shell
  ];
}
