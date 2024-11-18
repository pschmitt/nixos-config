{ pkgs, ... }:
{
  imports = [
    ./network.nix
    ./netbird.nix
    ./tailscale.nix
    ./zerotier.nix
  ];

  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];
}
