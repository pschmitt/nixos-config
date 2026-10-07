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
  # fzf-preview: the --preview helper the zsh fzf plugin and functions use.
  home.packages = lib.optionals (!termuxMode) [
    pkgs.fzf
    pkgs.fzf-preview
  ];

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

  xdg.configFile."zsh/termux/fzf-init.zsh" = lib.mkIf termuxMode {
    source = "${fzfInitFile}/init.zsh";
  };
}
