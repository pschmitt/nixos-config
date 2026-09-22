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
    ./user-services.nix
    ./wacom.nix
  ];
}
