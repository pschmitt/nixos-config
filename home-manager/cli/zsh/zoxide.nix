{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  zoxideInitFile = pkgs.runCommand "zoxide-init" { } ''
    mkdir -p $out
    ${pkgs.zoxide}/bin/zoxide init zsh --no-cmd > $out/init.zsh
  '';
in
{
  home.packages = lib.optionals (!termuxMode) [ pkgs.zoxide ];

  termux.packages = lib.mkIf termuxMode [ "zoxide" ];

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
    if termuxMode then
      ''
        # zoxide
        source "$TERMUX_GENERATION/home/.config/zsh/termux/zoxide-init.zsh"
        alias z=__zoxide_z
        alias zz=__zoxide_zi
      ''
    else
      ''
        # zoxide
        source ${zoxideInitFile}/init.zsh
        alias z=__zoxide_z
        alias zz=__zoxide_zi
      ''
  );

  xdg.configFile."zsh/termux/zoxide-init.zsh".source =
    lib.mkIf termuxMode "${zoxideInitFile}/init.zsh";
}
