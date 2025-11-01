{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bitwarden-desktop
    master.bitwarden-cli
    rbw
  ];
}
