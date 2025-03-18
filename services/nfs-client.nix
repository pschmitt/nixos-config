{ ... }:

let
  serverAddress = "rofl-02.netbird.cloud:/export";
  mounts = [
    "backups"
    "blobs"
    "books"
    "documents"
    "mnt"
    "srv"
    "tmp"
    "videos"
  ];
in
{
  fileSystems = builtins.listToAttrs (
    map (dir: {
      name = "/mnt/data/${dir}";
      value.device = "${serverAddress}/${dir}";
      value.fsType = "nfs";
      value.options = [
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=600"
      ];
    }) mounts
  );
}
