{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.nix-index-database.homeModules.nix-index ];

  programs.nix-index-database.comma.enable = true;

  # command-not-found integration
  programs.zsh.initContent = lib.mkOrder 710 ''
    if [[ -o interactive ]]
    then
      source ${
        inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}.nix-index-with-db
      }/etc/profile.d/command-not-found.sh
    fi
  '';
}
