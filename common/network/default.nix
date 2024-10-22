{ ... }:
{
  imports = [
    ./network.nix
    ./netbird.nix
    ./tailscale.nix
    ./zerotier.nix
  ];
}
