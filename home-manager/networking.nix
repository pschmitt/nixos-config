{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    hostctl
    iftop
    nethogs
    openssl
    tcpdump
    termshark
    traceroute
    inputs.vodafone-station-cli.packages.${pkgs.stdenv.hostPlatform.system}.vodafone-station-cli
    whois
  ];
}
