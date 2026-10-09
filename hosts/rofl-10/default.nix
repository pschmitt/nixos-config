{
  imports = [
    ../../profiles/base/users/k8s-backdoor.nix
    ../../profiles/features/network/ha-sshfs.nix
    ../../profiles/features/network/roflnet.nix
    ../../profiles/specializations/server

    ./browserless-public.nix
    ./disk-config.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./host.nix
    ./nfs.nix
    ./nix-cache.nix
    ./rclone-bisync.nix
    ./service-identities.nix
    ./services.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
