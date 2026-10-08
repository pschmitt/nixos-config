{
  imports = [
    ../../profiles/base/users/home-assistant.nix
    ../../profiles/features/network/roflnet.nix
    ../../profiles/specializations/server

    ./audit.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./host.nix
    ./nfs-client.nix
    ./services.nix
  ];
}
