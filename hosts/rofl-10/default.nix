{
  imports = [
    ../../profiles/base/users/k8s-backdoor.nix
    ../../profiles/features/network/ha-sshfs.nix
    ../../profiles/features/network/roflnet.nix
    ../../profiles/specializations/server

    ./disk-config.nix
    ./hardware-configuration.nix
    ./hardware.nix
    ./host.nix
    ./nfs.nix
    ./nix-cache.nix
    ./rclone-bisync.nix
    ./service-identities.nix
    ./services.nix
  ];
}
