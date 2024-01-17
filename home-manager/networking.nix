{ pkgs, ... }: {
  home.packages = with pkgs; [
    iftop
    nethogs
    tcpdump
    traceroute
    wireshark
  ];
}
