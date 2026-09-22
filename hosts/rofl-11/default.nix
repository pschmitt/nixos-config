{
  imports = [
    ../../profiles/features/network/roflnet.nix
    ../../profiles/specializations/server

    ./hardware-configuration.nix
    ./hardware.nix
    ./host.nix
    ./nfs.nix
    ./packages.nix
    ./services.nix
  ];
}
