{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  fzfInitFile = pkgs.runCommand "fzf-init" { } ''
    mkdir -p $out
    ${pkgs.fzf}/bin/fzf --zsh > $out/init.zsh
  '';
in
{
  home.packages = lib.optionals (!termuxMode) [ pkgs.fzf ];

  termux.packages = lib.mkIf termuxMode [ "fzf" ];

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
    if termuxMode then
      ''
        # fzf
        source "$TERMUX_GENERATION/home/.config/zsh/termux/fzf-init.zsh"
      ''
    else
      ''
        # fzf
        source ${fzfInitFile}/init.zsh
      ''
  );

  xdg.configFile."zsh/termux/fzf-init.zsh".source = lib.mkIf termuxMode "${fzfInitFile}/init.zsh";
}
