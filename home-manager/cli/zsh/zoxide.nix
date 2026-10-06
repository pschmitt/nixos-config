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
  termux.packages = lib.mkIf termuxMode [ "zoxide" ];
  home.packages = lib.optionals (!termuxMode) [ pkgs.zoxide ];

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
    if termuxMode then
      ''
        # zoxide
        eval "$(zoxide init zsh --no-cmd)"
        alias z=__zoxide_z
        alias zz=__zoxide_zi
      ''
    else
      ''
        # zoxide
        source ${
          (pkgs.runCommand "zoxide-init" { } ''
            mkdir -p $out
            ${pkgs.zoxide}/bin/zoxide init zsh --no-cmd > $out/init.zsh
          '')
        }/init.zsh
        alias z=__zoxide_z
        alias zz=__zoxide_zi
      ''
  );
}
