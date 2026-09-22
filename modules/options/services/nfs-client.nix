{ config, lib, ... }:
{
  options.services.nfsMounts = {
    enable = lib.mkEnableOption "NFS export client mounts";

    server = lib.mkOption {
      type = lib.types.str;
      default = "rofl-10.${config.domains.vpn}";
      description = "Hostname of the NFS export server";
    };

    exportPath = lib.mkOption {
      type = lib.types.path;
      default = "/export";
      description = "Remote export path on the NFS server; /export is the NFSv4 pseudoroot";
    };

    mountPoint = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/data";
      description = "Local base path under which exports are mounted";
    };

    exports = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "backups"
        "blobs"
        "documents"
        "mnt"
        "srv"
        "tmp"
      ];
      description = "Directory names (relative to exportPath/mountPoint) to mount";
    };
  };
}
