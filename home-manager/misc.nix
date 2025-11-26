{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    caligula # disk imaging

    eget
    home-assistant-cli
    linkding-cli
    withoutbg

    # todoist cli
    inputs.tdc.packages."${pkgs.stdenv.hostPlatform.system}".tdc

    # Below allows exporting address books from Evolution
    # we use this in ~zpl/contacts.zsh
    (pkgs.writeShellScriptBin "addressbook-export" ''
      exec ${pkgs.evolution-data-server}/libexec/evolution-data-server/addressbook-export "$@"
    '')
  ];
}
