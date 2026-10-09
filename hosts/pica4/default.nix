{
  imports = [
    ../../profiles/base
    ../../profiles/features/network
    ../../profiles/features/network/wifi.nix
    ../../profiles/specializations/server/interactive/dotfiles.nix

    ./hardware-configuration.nix
    ./hardware.nix
    ./networking.nix
    ./packages.nix
    ./services.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
