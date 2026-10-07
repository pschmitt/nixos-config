{ pkgs, ... }:
{
  # Clipboard helper (tmux copy-command, clipper, zsh functions). zinit
  # hosts get the script from yadm's ~/bin instead.
  home.packages = [ pkgs.xcp ];
}
