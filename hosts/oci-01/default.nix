{
  imports = [
    ../../profiles/specializations/server
    ../../services/luks-ssh-unlock/push-client.nix

    ./disk-config.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./install.nix
    ./luks-data.nix
    ./services.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
