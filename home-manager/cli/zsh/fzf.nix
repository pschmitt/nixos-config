{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxFzf = pkgs.callPackage ../../../pkgs/termux-native/go-binary.nix {
    inherit pkgs;
    package = pkgs.fzf;
    binary = "fzf";
  };
  fzfInitFile = pkgs.runCommand "fzf-init" { } ''
    mkdir -p $out
    ${pkgs.fzf}/bin/fzf --zsh > $out/init.zsh
  '';
in
{
  home.packages = if termuxMode then [ termuxFzf ] else [ pkgs.fzf ];

  xdg.configFile."zsh/custom/os/home-manager/system.zsh" = lib.mkIf (!termuxMode) {
    text = lib.mkAfter ''
      # fzf
      source ${fzfInitFile}/init.zsh
    '';
  };
}
