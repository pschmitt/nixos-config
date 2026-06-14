# syncthing — declarative Syncthing with shared device list.
{
  imports = [ ./syncthing-devices.nix ];

  custom.syncthing.enable = true;
}
