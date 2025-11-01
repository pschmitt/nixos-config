{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    iftop
    nethogs
    tcpdump
    termshark
    traceroute
    inputs.vodafone-station-cli.packages.${stdenv.hostPlatform.system}.vodafone-station-cli
    whois
  ];
}
