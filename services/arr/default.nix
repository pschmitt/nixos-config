{ lib, ... }:
{
  imports = [
    ./vpn.nix
    ./arr-service.nix

    # services
    ./fake-hosts.nix
    ./flaresolverr.nix
    ./jackett.nix
    # ./listenarr.nix  # superseded by shelfarr
    # ./cwabd.nix      # superseded by shelfarr
    ./malware-filter.nix
    ./microsocks.nix
    ./podman-net.nix
    ./prowlarr.nix
    ./radarr.nix
    ./recyclarr.nix
    ./shadowsocks.nix
    ./shelfarr.nix
    ./sonarr.nix
    ./transmission.nix
  ];

  systemd.targets.arr.description = "Bundle target for arr services";

  virtualisation.oci-containers.backend = lib.mkForce "podman";
}
