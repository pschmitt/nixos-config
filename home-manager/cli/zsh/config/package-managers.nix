{ lib, pkgs, ... }:
{
  home.packages = [ pkgs.update-and-deploy ];

  programs.zsh = {
    shellAliases = {
      y = "nix search nixpkgs";
      yup = "update-and-deploy";
      yupnc = "update-and-deploy --flake-update --print-build-logs";
    };

    initContent = lib.mkOrder 1150 ''
      # Usage: ync PACKAGE... -- a shell with these nixpkgs packages
      ync() {
        if (( $# == 0 ))
        then
          print -ru2 -- 'Usage: ync PACKAGE...'
          return 2
        fi
        nix shell "''${@/#/nixpkgs#}"
      }
    '';
  };
}
