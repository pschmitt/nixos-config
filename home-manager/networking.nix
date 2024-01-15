{ pkgs, ... }: {
  home.packages = [
    pkgs.iftop
    pkgs.nethogs
    pkgs.tcpdump
    pkgs.wireshark
  ];
}
