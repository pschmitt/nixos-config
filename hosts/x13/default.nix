{
  imports = [
    ../../profiles/specializations/workstation
    ../../services/nixos-installer-boot-entry.nix

    ./fprintd.nix
    ./hardware-configuration.nix
    ./jellysync.nix
    ./networking.nix
  ];
}
