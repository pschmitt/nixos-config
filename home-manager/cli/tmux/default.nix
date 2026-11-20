{
  programs.tmux = {
    enable = false;
    extraConfig = ''
      set -g mouse on
      set -g history-limit 100000
    '';
  };
}
