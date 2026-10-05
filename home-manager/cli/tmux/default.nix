{
  config,
  lib,
  ...
}:
let
  termuxMode = config.termux.enable or false;
in
{
  programs.tmux = {
    enable = termuxMode;
    extraConfig = ''
      set -g mouse on
      set -g history-limit 100000
    '';
  }
  // lib.optionalAttrs termuxMode {
    package = null;
    shell = "/data/data/com.termux/files/usr/bin/zsh";
  };

  home.sessionVariables = lib.mkIf termuxMode {
    TMUX_TMPDIR = lib.mkForce "/data/data/com.termux/files/usr/tmp";
  };

  termux.packages = lib.mkIf termuxMode [ "tmux" ];
}
