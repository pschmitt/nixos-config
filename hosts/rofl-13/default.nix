{
  imports = [
    ../../modules/disko/openstack-luks-btrfs.nix
    ../../profiles/specializations/rofl-build-node
    ../../services/luks-ssh-unlock/push-client.nix

    ./prompt.nix
  ];

  hardware.disko.openstack.rootDiskId =
    (builtins.fromJSON (builtins.readFile ./tf-vars.json)).disks.root.id;

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
