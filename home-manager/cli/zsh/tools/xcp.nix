{ pkgs, ... }:
{
  # Clipboard helper (tmux copy-command, clipper, zsh functions).
  home.packages = [ pkgs.xcp ];
}
