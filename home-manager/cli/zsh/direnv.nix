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
in
{
  home.packages = if termuxMode then [ termuxDirenv ] else [ pkgs.direnv ];

  programs.direnv = {
    enable = !termuxMode;
    nix-direnv.enable = !termuxMode;
    silent = true;
  };

  xdg.configFile."zsh/custom/os/home-manager/system.zsh".text = lib.mkAfter (
    if termuxMode then
      ''
        # direnv
        eval "$(direnv hook zsh)"
        export DIRENV_LOG_FORMAT=
      ''
    else
      ''
        # direnv
        source ${
          (pkgs.runCommand "direnv-init" { } ''
            mkdir -p $out
            ${pkgs.direnv}/bin/direnv hook zsh > $out/init.zsh
          '')
        }/init.zsh
      ''
  );
}
