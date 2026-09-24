{ pkgs, ... }:
{
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "rclone-bisync-recover" ''
      set -euo pipefail

      # The launcher clears only a stale rclone lock and invokes --recover.
      systemctl start rclone-bisync-documents.service
    '')
  ];
}
