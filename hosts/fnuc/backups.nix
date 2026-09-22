_: {
  services.restic.backups.main = {
    paths = [
      "/srv"
      "/mnt/sda1"
    ];

    exclude = [
      "/var/lib/libvirt/images"
      "/var/lib/libvirt/qemu/save"
      "/var/lib/libvirt/qemu/snapshot"
      "/mnt/sda1/replicas"
      "/mnt/sda1/engine-binaries"
    ];

    # The VM disk is not a coherent backup while the guest is running. HA's
    # guest-native backups remain the restore source for the VM itself.
  };

  systemd.services.restic-backups-main.unitConfig = {
    RequiresMountsFor = [ "/mnt/sda1" ];
    ConditionPathIsMountPoint = "/mnt/sda1";
  };
}
