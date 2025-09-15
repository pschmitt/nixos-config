{
  server ? "rofl-10.netbird.cloud",
  exportPath ? "/export",
  mountPoint ? "/mnt/data",
  exports ? [
    "backups"
    "blobs"
    "books"
    "documents"
    "mnt"
    "srv"
    "tmp"
    # "videos" # lives on rofl-11 now
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
    }) exports
  );
}
