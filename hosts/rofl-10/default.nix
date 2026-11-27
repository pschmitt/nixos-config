{
  imports = [
    ../../modules/disko/openstack-luks-btrfs.nix
    ../../profiles/base/users/github-actions.nix
    ../../profiles/base/users/k8s-backdoor.nix
    ../../profiles/features/network/ha-sshfs.nix
    ../../profiles/features/network/roflnet.nix
    ../../profiles/specializations/server
    ../../services/luks-ssh-unlock/push-client.nix

    ./browserless-public.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./host.nix
    ./nfs.nix
    ./nix-cache.nix
    ./rclone-bisync.nix
    ./service-identities.nix
    ./services.nix
    ./storage.nix
  ];

  hardware.disko.openstack.rootDiskId =
    (builtins.fromJSON (builtins.readFile ./tf-vars.json)).disks.root.id;

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
