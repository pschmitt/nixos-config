# syncthing — declarative Syncthing with shared device list.
{
  imports = [
    ./syncthing/devices.nix
    ./syncthing/web.nix
  ];

  services.syncthing.managed.enable = true;
}
