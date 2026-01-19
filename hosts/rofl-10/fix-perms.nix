{
  # Fix permissions after UID changes (e.g., after reinstall)
  systemd.tmpfiles.rules = [
    # Fix ISO upload directory ownership (readable by nginx)
    "Z /mnt/data/blobs/iso 0755 github-actions nginx - -"
    # Fix IMG upload directory ownership (readable by nginx)
    "Z /mnt/data/blobs/img 0755 github-actions nginx - -"
  ];
}
