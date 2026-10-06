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
  termux.packages = lib.mkIf termuxMode [ "fzf" ];
  home.packages = lib.optionals (!termuxMode) [ pkgs.fzf ];

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
    if termuxMode then
      ''
        # fzf
        eval "$(fzf --zsh)"
      ''
    else
      ''
        # fzf
        source ${
          (pkgs.runCommand "fzf-init" { } ''
            mkdir -p $out
            ${pkgs.fzf}/bin/fzf --zsh > $out/init.zsh
          '')
        }/init.zsh
      ''
  );
}
