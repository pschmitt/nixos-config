{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    iftop
    nethogs
    tcpdump
    termshark
    traceroute
    inputs.vodafone-station-cli.packages.${pkgs.stdenv.hostPlatform.system}.vodafone-station-cli
    whois
  ];
}
