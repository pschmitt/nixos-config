{
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    fzf
  ];

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter ''
    # fzf
    source ${
      (pkgs.runCommand "fzf-init" { } ''
        mkdir -p $out
        ${pkgs.fzf}/bin/fzf --zsh > $out/init.zsh
      '')
    }/init.zsh
  '';
}
