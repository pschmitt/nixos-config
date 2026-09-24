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
  ];
}
