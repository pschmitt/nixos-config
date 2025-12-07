{ lib, ... }:
{
  imports = [
    ./vpn.nix

    # services
    ./cwabd.nix
    ./fake-hosts.nix
    ./jackett.nix
    ./listenarr.nix
    ./microsocks.nix
    ./podman-net.nix
    ./shadowsocks.nix
    ./prowlarr.nix
    ./radarr.nix
    ./sonarr.nix
    ./transmission.nix
  ];

  virtualisation.oci-containers.backend = lib.mkForce "podman";

  users.groups.media = { };
}
