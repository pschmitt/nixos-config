{ ... }:
{
  imports = [
    ./vpn.nix

    # services
    ./transmission.nix
    ./sonarr.nix
    ./radarr.nix
    ./jackett.nix
    ./prowlarr.nix
    ./test.nix
  ];
}
