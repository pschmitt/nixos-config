args:
let
  server = args.server or "rofl-10.netbird.cloud";
  exportPath = args.exportPath or "/export";
  mountPoint = args.mountPoint or "/mnt/data";
  exports =
    args.exports or [
      "backups"
      "blobs"
      "books"
      "documents"
      "mnt"
      "srv"
      "tmp"
      # "videos" # lives on rofl-11 now
    ];
in

{
  fileSystems = builtins.listToAttrs (
    map (dir: {
      name = "${mountPoint}/${dir}";
      value = {
        device = "${server}:${exportPath}/${dir}";
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
