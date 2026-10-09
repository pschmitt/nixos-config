{
  imports = [
    ../../profiles/specializations/workstation
    ../../services/nixos-installer-boot-entry.nix

    ./gpd-power.nix
    ./hardware-configuration.nix
    ./initrd-wifi.nix
    ./kmscon.nix
    ./lan-mouse.nix
    ./network.nix
    ./noctalia.nix
    ./power.nix
    ./prompt.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
