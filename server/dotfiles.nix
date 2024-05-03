{ ... }: {
  programs.bash.vteIntegration = true;

  programs.tmux.extraConfig = ''
  set -g mouse on
  '';
}
