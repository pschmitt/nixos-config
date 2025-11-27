{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    eget
    home-assistant-cli
    linkding-cli
    withoutbg

    # Below allows exporting address books from Evolution
    # we use this in ~zpl/contacts.zsh
    (pkgs.writeShellScriptBin "addressbook-export" ''
      exec ${pkgs.evolution-data-server}/libexec/evolution-data-server/addressbook-export "$@"
    '')

    inputs.slack-react.packages.${pkgs.stdenv.hostPlatform.system}.slack-react

    # todoist cli
    inputs.tdc.packages."${pkgs.stdenv.hostPlatform.system}".tdc
  ];
}
