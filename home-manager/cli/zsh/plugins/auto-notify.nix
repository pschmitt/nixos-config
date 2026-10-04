{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  autoNotify = pkgs.fetchFromGitHub {
    owner = "MichaelAquilina";
    repo = "zsh-auto-notify";
    rev = "b51c934d88868e56c1d55d0a2a36d559f21cb2ee";
    hash = "sha256-s3TBAsXOpmiXMAQkbaS5de0t0hNC1EzUUb0ZG+p9keE=";
  };
in
{
  programs.zsh.initContent = lib.mkIf (!termuxMode) (
    lib.mkOrder 900 ''
      if [[ -o interactive && -z "''${NO_PLUGINS:-}" && -z "$SSH_CONNECTION" ]] \
        && (( $+commands[notify-send] )) \
        && ! is_termux
      then
        zsh::source-plugin ${autoNotify}/auto-notify.plugin.zsh
        export AUTO_NOTIFY_THRESHOLD=30 AUTO_NOTIFY_EXPIRE_TIME=5000
      fi
    ''
  );
}
