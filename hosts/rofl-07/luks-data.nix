{ lib, ... }:
{
  # Data volume
  boot.initrd.luks.devices.data-encrypted = {
    keyFile = lib.mkForce "/sysroot/luks-data.keyfile";
  };
}
