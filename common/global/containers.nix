{ ... }:
{
  # FIXME as of 2024-10-21 podman is failing to start more than one container
  # as root
  # Error: netavark: code: 1, msg: iptables: Chain already exists.
  # repro: sudo podman run -ti --rm ghcr.io/pschmitt/debug
  virtualisation.oci-containers.backend = "docker";
}
