{
  imports = [
    ../../profiles/features/network/roflnet.nix
    ../../profiles/specializations/server

    ./hardware-configuration.nix
    ./hardware.nix
    ./host.nix
    ./nfs.nix
    ./packages.nix
    ./services.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
