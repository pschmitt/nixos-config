{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    caligula # disk imaging

    eget
    home-assistant-cli

    # todoist cli
    inputs.tdc.packages."${system}".tdc
    todoist
  ];
}
