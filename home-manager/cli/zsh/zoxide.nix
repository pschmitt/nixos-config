{
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    zoxide
  ];

  xdg.configFile."zsh/custom/os/nixos/system.zsh".text = lib.mkAfter ''
    [[ -o interactive ]] || return

    # zoxide
    source ${
      (pkgs.runCommand "zoxide-init" { } ''
        mkdir -p $out
        ${pkgs.zoxide}/bin/zoxide init zsh --no-cmd > $out/init.zsh
      '')
    }/init.zsh
    alias z=__zoxide_z
    alias zz=__zoxide_zi
  '';
}
