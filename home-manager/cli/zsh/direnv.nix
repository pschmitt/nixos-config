{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxDirenv = pkgs.callPackage ../../../pkgs/termux-native/go-binary.nix {
    inherit pkgs;
    package = pkgs.direnv;
    binary = "direnv";
  };
  direnvInitFile = pkgs.runCommand "direnv-init" { } ''
    mkdir -p $out
    ${pkgs.direnv}/bin/direnv hook zsh > $out/init.zsh
  '';
in
{
  home.packages = if termuxMode then [ termuxDirenv ] else [ pkgs.direnv ];

  programs.direnv = {
    enable = !termuxMode;
    nix-direnv.enable = !termuxMode;
    silent = true;
  };

  xdg.configFile."zsh/custom/os/home-manager/system.zsh" = lib.mkIf (!termuxMode) {
    text = lib.mkAfter ''
      # direnv
      source ${direnvInitFile}/init.zsh
    '';
  };
}
