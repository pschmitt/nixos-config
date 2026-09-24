# syncthing — declarative Syncthing with shared device list.
{
  imports = [
    ./devices.nix
    ./web.nix
  ];

  services.syncthing.managed.enable = true;
}
