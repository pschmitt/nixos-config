{ config, ... }:
{
  # Start/attach tmux in interactive shells (plugins/local/tmux.zsh).
  home-manager.users.${config.mainUser.username}.programs.zsh.sessionVariables.TMUX_AUTOSTART = "1";
}
