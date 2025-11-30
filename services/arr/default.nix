{ lib, ... }:
{
  imports = [
    ./vpn.nix

    # services
    ./transmission.nix
    ./sonarr.nix
    ./radarr.nix
    ./jackett.nix
    ./prowlarr.nix
    ./cwabd.nix
    ./test.nix
  ];

  virtualisation.oci-containers.backend = lib.mkForce "podman";
}
