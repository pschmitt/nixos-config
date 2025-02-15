{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bitwarden
    master.bitwarden-cli
    rbw
  ];
}
