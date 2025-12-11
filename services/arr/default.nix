{ lib, ... }:
{
  imports = [
    ./vpn.nix

    # services
    ./cwabd.nix
    ./fake-hosts.nix
    ./flaresolverr.nix
    ./jackett.nix
    ./listenarr.nix
    ./microsocks.nix
    ./podman-net.nix
    ./prowlarr.nix
    ./radarr.nix
    ./shadowsocks.nix
    ./sonarr.nix
    ./transmission.nix
  ];

  systemd.targets.arr.description = "Bundle target for arr services";

  virtualisation.oci-containers.backend = lib.mkForce "podman";
}
