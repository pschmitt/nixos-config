{ lib, pkgs, ... }:
{
  home.packages = [ pkgs.update-and-deploy ];

  programs.zsh = {
    shellAliases = {
      y = "nix search nixpkgs";
      ync = "nix-shell --packages";
      yqo = "nix-env --query";
      yup = "update-and-deploy";
      yupnc = "update-and-deploy --flake-update --print-build-logs";
    };

    initContent = lib.mkOrder 1150 ''
      yrm() {
        if (( $# == 0 ))
        then
          print -ru2 -- 'Usage: yrm PACKAGE...'
          return 2
        fi

        nix-env --uninstall "$@" || return
        nix-collect-garbage --delete-older-than 7d
      }
    '';
  };
}
