{
  imports = [
    ../../profiles/specializations/homelab-server

    ./backups.nix
    ./browser.nix
    ./disk-config.nix
    ./fnuc-migration.nix
    ./hardware-configuration.nix
    ./hass-vm.nix
    ./initrd-data-unlock.nix
    ./networking.nix
    ./prompt.nix
    ./services.nix
    ./user-services.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
