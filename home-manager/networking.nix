{ inputs, pkgs, ... }:
{
  home.packages = with pkgs; [
    hostctl
    iftop
    net-snmp
    nethogs
    openssl
    tcpdump
    termshark
    traceroute
    inputs.vodafone-station-cli.packages.${pkgs.stdenv.hostPlatform.system}.vodafone-station-cli
    whois
  ];
}
