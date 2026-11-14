# rworker: a disposable Nix remote builder for nixbot, booted from an
# OpenStack image and created/deleted on demand by the autoscaler on the
# nixbot host. See README.md.
#
# Not built with mkHost: it carries no secrets and no sops age key, so it
# must not import profiles/base. Everything it needs at runtime (the NetBird
# setup key) arrives once through the OpenStack user-data.
{
  imports = [
    ./builder.nix
    ./disk.nix
    ./image.nix
    ./netbird.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "26.11";
}
