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
in
{
  home.packages = if termuxMode then [ termuxFzf ] else [ pkgs.fzf ];

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
