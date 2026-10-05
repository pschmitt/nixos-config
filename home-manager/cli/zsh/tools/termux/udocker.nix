{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
in
{
  home.packages = lib.optionals (!termuxMode) [ pkgs.udocker ];
  termux.packages = lib.mkIf termuxMode [ "udocker" ];

  programs.zsh.envExtra = lib.mkIf termuxMode ''
    export UDOCKER_DIR="$XDG_DATA_HOME/udocker"
    export UDOCKER_USE_PROOT_EXECUTABLE="$PREFIX/bin/proot"
    export UDOCKER_DEFAULT_EXECUTION_MODE=P1
  '';
}
