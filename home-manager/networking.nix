{ pkgs, ... }:
{
  home.packages = with pkgs; [
    iftop
    nethogs
    tcpdump
    termshark
    traceroute
    whois
    wireshark
  ];
}
