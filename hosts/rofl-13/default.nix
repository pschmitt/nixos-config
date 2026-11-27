{
  imports = [
    ../../profiles/specializations/rofl-build-node
    ../../services/luks-ssh-unlock/push-client.nix

    ./hardware-configuration.nix
    ./prompt.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
