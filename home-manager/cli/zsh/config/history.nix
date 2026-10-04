{ config, ... }:
{
  programs.zsh = {
    history = {
      path = "${config.xdg.stateHome}/zsh/zhistory";
      size = 10000;
      save = 10000;
      extended = true;
      ignoreDups = true;
      ignoreAllDups = false;
      saveNoDups = true;
      findNoDups = true;
      share = true;
      ignoreSpace = true;
    };
    sessionVariables = {
      HISTFILE = "${config.xdg.stateHome}/zsh/zhistory";
      HISTSIZE = 10000;
      SAVEHIST = 10000;
    };
    initContent = ''
      mkdir -p -- "${config.xdg.stateHome}/zsh"
      setopt HIST_REDUCE_BLANKS HIST_VERIFY APPEND_HISTORY RC_QUOTES
    '';
  };
}
