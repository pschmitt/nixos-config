# syncthing — declarative Syncthing with shared device list.
{
  imports = [ ./syncthing/devices.nix ];

  services.syncthing.declarative.enable = true;
}
