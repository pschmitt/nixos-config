{ lib, ... }:
{
  imports = [
    ./vpn.nix

    # services
    ./cwabd.nix
    ./jackett.nix
    ./listenarr.nix
    ./podman-net.nix
    ./prowlarr.nix
    ./radarr.nix
    ./sonarr.nix
    ./transmission.nix
  ];

  virtualisation.oci-containers.backend = lib.mkForce "podman";
}
