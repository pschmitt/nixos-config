{ config, lib, ... }:
let
  cfg = config.services.nfsMounts;
in
{
  options.services.nfsMounts = {
    enable = lib.mkEnableOption "NFS export client mounts";

    server = lib.mkOption {
      type = lib.types.str;
      default = "rofl-10.${config.domains.netbird}";
      description = "Hostname of the NFS export server";
    };

    exportPath = lib.mkOption {
      type = lib.types.path;
      default = "/export";
      description = "Remote export path on the NFS server";
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

  config = lib.mkIf cfg.enable {
    fileSystems = builtins.listToAttrs (
      map (dir: {
        name = "${cfg.mountPoint}/${dir}";
        value = {
          device = "${cfg.server}:${cfg.exportPath}/${dir}";
          fsType = "nfs";
          options = [
            "noauto"
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "soft"
            "timeo=50"
            "retrans=3"
          ];
        };
      }) cfg.exports
    );
  };
}
