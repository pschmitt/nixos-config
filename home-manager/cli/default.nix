{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
in
{
  imports = [
    ./core.nix
    ./nvim
  ];

  home.packages = lib.optionals (!termuxMode) [
    pkgs.atuin
    pkgs.direnv
    pkgs.emoji-fzf
    pkgs.fzf
    pkgs.linkding-cli

    # Image background removal tools.
    pkgs.backgroundremover
    pkgs.withoutbg

    # Used by ~zpl/contacts.zsh on desktop hosts.
    (pkgs.writeShellScriptBin "addressbook-export" ''
      exec ${pkgs.evolution-data-server}/libexec/evolution-data-server/addressbook-export "$@"
    '')
  ];
}
