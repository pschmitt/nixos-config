{ pkgs, ... }:
{
  home.packages = with pkgs; [
    iftop
    nethogs
    termshark
    tcpdump
    traceroute
    wireshark
  ];
}
