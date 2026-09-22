{
  imports = [
    ../../profiles/specializations/homelab-server

    ./backups.nix
    ./browser.nix
    ./disk-config.nix
    ./fnuc-migration.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./hass-vm.nix
    ./initrd-data-unlock.nix
    ./kmscon.nix
    ./networking.nix
    ./services.nix
    ./user-services.nix
  ];
}
