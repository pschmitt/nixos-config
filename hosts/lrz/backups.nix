{ pkgs, ... }:
{
  # FNUC-015: This host holds persistent service data. This also enables the
  # shared restic service and its existing host-specific runtime SOPS secrets.
  hardware.cattle = false;

  services.restic.backups.main = {
    # The migration coordinator creates this lock as pschmitt:users. Wrap the
    # actual restic process: backupPrepareCommand runs in a separate process
    # and cannot hold a descriptor open for the subsequent backup command.
    package = pkgs.writeShellScriptBin "restic" ''
      exec ${pkgs.util-linux}/bin/flock --exclusive --timeout 300 \
        /var/lib/fnuc-migration/lock ${pkgs.restic}/bin/restic "$@"
    '';

    # /etc, /var/lib and the main user's home come from profiles/server/restic.
    paths = [
      "/srv"
      "/mnt/sda1"
    ];

    exclude = [
      # A running guest's disk (or its in-progress warm copy) is not a coherent
      # backup. Include VM disks only after a separate quiesced/export workflow
      # exists; HA's guest-native backups need their own restore verification.
      "/var/lib/libvirt/images"
      "/var/lib/libvirt/qemu/save"
      "/var/lib/libvirt/qemu/snapshot"

      # Retired Longhorn storage is deliberately not migrated from fnuc.
      "/mnt/sda1/replicas"
      "/mnt/sda1/engine-binaries"
    ];
  };

  # Refuse to back up an empty directory on the root disk if SATA is missing.
  systemd.services.restic-backups-main.unitConfig = {
    RequiresMountsFor = [ "/mnt/sda1" ];
    ConditionPathIsMountPoint = "/mnt/sda1";
  };
}
