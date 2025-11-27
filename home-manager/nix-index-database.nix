{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.nix-index-database.homeModules.nix-index ];

  programs.nix-index-database.comma.enable = true;

  xdg.configFile."zsh/custom/os/nixos/system.zsh".text = lib.mkAfter ''
    # command-not-found integration
    source ${
      inputs.nix-index-database.packages.${pkgs.stdenv.hostPlatform.system}.nix-index-with-db
    }/etc/profile.d/command-not-found.sh
  '';
}
