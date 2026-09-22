{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "rclone-bisync-reset-and-resync" ''
      set -euo pipefail

      lockfile="/var/cache/rclone/bisync/nextcloud_Documents..drive_Documents.lck"

      systemctl stop rclone-bisync-documents.service rclone-bisync-documents-resync.service
      rm -f "$lockfile"
      systemctl start rclone-bisync-documents-resync.service
    '')
  ];
}
