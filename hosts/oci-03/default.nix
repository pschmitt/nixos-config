{
  imports = [
    ../../profiles/specializations/server

    ./disk-config.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
