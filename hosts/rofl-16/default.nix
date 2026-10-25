{
  imports = [
    ../../profiles/specializations/rofl-build-node

    ./hardware-configuration.nix
    ./networking.nix
    ./prompt.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "26.11";
}
