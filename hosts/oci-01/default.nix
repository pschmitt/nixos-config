{
  imports = [
    ../../profiles/specializations/server

    ./disk-config.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./install.nix
    ./luks-data.nix
    ./networking.nix
    ./services.nix
  ];
}
