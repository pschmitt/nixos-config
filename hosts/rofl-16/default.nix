{
  imports = [
    ../../modules/disko/openstack-luks-btrfs.nix
    ../../profiles/specializations/rofl-build-node
    ../../services/luks-ssh-unlock/push-client.nix
    ../../services/circus/agent.nix

    ./prompt.nix
  ];

  hardware.disko.openstack.rootDiskId =
    (builtins.fromJSON (builtins.readFile ./tf-vars.json)).disks.root.id;

  # Circus CI trial (services/circus/README.md): agents reach the
  # queue-runner on rofl-15.
  services.circus.agent.runnerHost = "rofl-15";

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "26.11";
}
