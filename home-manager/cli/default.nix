{ pkgs, ... }:
{
  imports = [
    ./core.nix
    ./nvim
    ./ssh-tools.nix
    ./workstation-tools.nix
  ];

  home.packages = [
    pkgs.atuin
    pkgs.direnv
    pkgs.fzf

    # Image background removal tools.
    pkgs.backgroundremover
    pkgs.withoutbg

    # Used by ~zpl/contacts.zsh on desktop hosts.
    (pkgs.writeShellScriptBin "addressbook-export" ''
      exec ${pkgs.evolution-data-server}/libexec/evolution-data-server/addressbook-export "$@"
    '')
  ];
}
