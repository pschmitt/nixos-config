{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    eget
    home-assistant-cli

    # todoist cli
    inputs.tdc.packages."${system}".tdc
    todoist
  ];
}
