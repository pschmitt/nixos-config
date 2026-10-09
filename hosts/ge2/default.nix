{
  imports = [
    ../../profiles/features/work/elgato-stream-deck.nix
    ../../profiles/specializations/workstation

    ./boot.nix
    ./crash-diagnostics.nix
    ./falcon-sensor-vm.nix
    ./gdm.nix
    ./hardware-configuration.nix
    ./initrd-wifi.nix
    ./kmscon.nix
    ./lan-mouse.nix
    ./networking.nix
    ./noctalia-obs.nix
    ./prompt.nix
    ./user-services.nix
    ./wacom.nix
  ];

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
