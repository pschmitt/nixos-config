{ config, ... }:
{
  programs.zsh = {
    setOptions = [
      "HIST_REDUCE_BLANKS"
      "HIST_VERIFY"
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
      # Home Manager emits `unsetopt APPEND_HISTORY` otherwise (yadm sets it).
      append = true;
    };
    # HISTFILE/HISTSIZE/SAVEHIST come from `history` as plain shell
    # parameters; exporting them would make child shells (bash) write to the
    # zsh history file.
  };
}
