{
  server ? "rofl-02.netbird.cloud",
  exportPath ? "/export",
  mountPoint ? "/mnt/data",
  mounts ? [
    "backups"
    "blobs"
    "books"
    "documents"
    "mnt"
    "srv"
    "tmp"
    "videos"
  ],
  ...
}:

{
  fileSystems = builtins.listToAttrs (
    map (dir: {
      name = "${mountPoint}/${dir}";
      value.device = "${server}:${exportPath}/${dir}";
      value.fsType = "nfs";
      value.options = [
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=600"
      ];
    }) mounts
  );
}
