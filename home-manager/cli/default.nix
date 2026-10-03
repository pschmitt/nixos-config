{ pkgs, ... }:
{
  imports = [
    ./bat.nix
    ./eza.nix
    ./fd.nix
    ./nvim
    ./ripgrep.nix
    ./tmux
    ./zsh
  ];

  home.packages = with pkgs; [
    atuin
    direnv
    eget
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
