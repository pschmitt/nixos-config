{ pkgs, ... }:
{
  imports = [
    ./core.nix
    ./nvim
  ];

  home.packages = with pkgs; [
    atuin
    direnv
    emoji-fzf
    fzf
    linkding-cli

    # img background removal tools
    backgroundremover
    withoutbg

    # Below allows exporting address books from Evolution
    # we use this in ~zpl/contacts.zsh
    (pkgs.writeShellScriptBin "addressbook-export" ''
      exec ${pkgs.evolution-data-server}/libexec/evolution-data-server/addressbook-export "$@"
    '')
  ];
}
