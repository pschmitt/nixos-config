{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  direnvInitFile = pkgs.runCommand "direnv-init" { } ''
    mkdir -p $out
    ${pkgs.direnv}/bin/direnv hook zsh > $out/init.zsh
  '';
in
{
  home.packages = lib.optionals (!termuxMode) [ pkgs.direnv ];

  termux.packages = lib.mkIf termuxMode [ "direnv" ];

  programs.direnv = {
    enable = !termuxMode;
    nix-direnv.enable = !termuxMode;
    silent = true;
  };

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
    if termuxMode then
      ''
        # direnv
        eval "$(direnv hook zsh)"
        export DIRENV_LOG_FORMAT=
      ''
    else
      ''
        # direnv
        source ${direnvInitFile}/init.zsh
      ''
  );
}
