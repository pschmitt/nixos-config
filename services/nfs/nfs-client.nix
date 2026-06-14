{
  server ? null,
  exportPath ? "/export",
  mountPoint ? "/mnt/data",
  exports ? [
    "backups"
    "blobs"
    "documents"
    "mnt"
    "srv"
    "tmp"
    # "videos" # lives on rofl-11
    # "books"  # lives on rofl-11
  ],
}:
{ config, ... }:
let
  resolvedServer = if server == null then "rofl-10.${config.domains.netbird}" else server;
in

{
  fileSystems = builtins.listToAttrs (
    map (dir: {
      name = "${mountPoint}/${dir}";
      value = {
        device = "${resolvedServer}:${exportPath}/${dir}";
        fsType = "nfs";
        options = [
          "noauto"
          "x-systemd.automount"
          "x-systemd.idle-timeout=600"
        ];
      };
    }) exports
  );
}
