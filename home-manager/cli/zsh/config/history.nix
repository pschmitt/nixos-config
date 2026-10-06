{ config, ... }:
{
  programs.zsh = {
    setOptions = [
      "HIST_REDUCE_BLANKS"
      "HIST_VERIFY"
      "APPEND_HISTORY"
    ];

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
  };
}
