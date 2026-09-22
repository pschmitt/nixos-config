# syncthing — declarative Syncthing with shared device list.
{
  imports = [ ./syncthing/devices.nix ];

  services.syncthing.managed.enable = true;
}
