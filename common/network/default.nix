{ pkgs, ... }:
{
  imports = [
    ./network.nix
    ./netbird.nix
    ./tailscale.nix
    ./zerotier.nix
  ];

  environment.systemPackages = with pkgs; [
    curl
    fping
    nethogs
    nmap
    ookla-speedtest
    tcpdump
    wireguard-tools
  ];
}
