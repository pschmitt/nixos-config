{
  imports = [
    ../../modules/disko/openstack-luks-btrfs.nix
    ../../profiles/base/users/home-assistant.nix
    ../../profiles/features/network/roflnet.nix
    ../../profiles/specializations/server
    ../../services/luks-ssh-unlock/push-client.nix

    ./hardware.nix
    ./host.nix
    ./nfs-client.nix
    ./services.nix
  ];

  hardware.disko.openstack = {
    rootDiskId = (builtins.fromJSON (builtins.readFile ./tf-vars.json)).disks.root.id;
    extraSubvolumes."@monero-wallet-rpc" = "/var/lib/monero-wallet-rpc";
  };

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
