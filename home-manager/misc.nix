{ pkgs, ... }:
{
  home.packages = with pkgs; [
    eget
    home-assistant-cli

    # todoist cli
    tdc
    todoist
  ];
}
