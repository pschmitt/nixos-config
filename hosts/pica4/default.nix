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
}
