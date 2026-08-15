{ inputs, pkgs, ... }:
{
  imports = [
    ./nvim.nix
    ./zsh
    ../../modules/home-manager/todoist-cli.nix
  ];

  home.packages = with pkgs; [
    atuin
    bat
    direnv
    eget
    emoji-fzf
    eza
    fd
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

    # todoist cli
    inputs.tdc.packages."${pkgs.stdenv.hostPlatform.system}".tdc
    todoist-cli
  ];
}
