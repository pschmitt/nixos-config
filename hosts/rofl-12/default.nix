{
  imports = [
    ../../profiles/base/users/home-assistant.nix
    ../../profiles/features/network/roflnet.nix
    ../../profiles/specializations/server

    ./audit.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./host.nix
    ./nfs-client.nix
    ./services.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
