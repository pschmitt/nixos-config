{
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    direnv
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true;
  };

  xdg.configFile."zsh/custom/os/nixos/system.zsh".text = lib.mkAfter ''
    # direnv
    source ${
      (pkgs.runCommand "direnv-init" { } ''
        mkdir -p $out
        ${pkgs.direnv}/bin/direnv hook zsh > $out/init.zsh
      '')
    }/init.zsh
  '';
}
