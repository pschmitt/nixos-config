{ lib, ... }:
{
  imports = [
    ../../profiles/hardware/rpi4.nix
    ./config-txt.nix
    ./power-monitoring.nix
  ];

  # Root is ext4 and there are no pools; ZFS support only came in by default
  # (and with it the boot.zfs.forceImportRoot warning).
  boot.supportedFilesystems.zfs = lib.mkForce false;
}
