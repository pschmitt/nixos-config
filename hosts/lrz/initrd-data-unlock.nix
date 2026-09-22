{ lib, ... }:
{
  # Auto-unlock the encrypted data volume in initrd using the key on root.
  boot.initrd.luks.devices.data-encrypted.keyFile =
    lib.mkForce "/sysroot/etc/crypttab.d/keyfiles/data";
}
