{ lib, ... }:
{
  options.services.nfsExports = {
    enable = lib.mkEnableOption "NFS export server";

    allowedIps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "100.64.0.0/10" ]; # cg-nat, ie tailscale/netbird
      description = "CIDRs allowed to mount the NFS exports";
    };

    basePath = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/data";
      description = "Base path containing the directories to export, bind-mounted under exportPath";
    };

    exportPath = lib.mkOption {
      type = lib.types.path;
      default = "/export";
      description = "Path under which exports are bind-mounted and served";
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
      description = "Directory names (relative to basePath/exportPath) to export via NFS";
    };

    exportOptions = lib.mkOption {
      type = lib.types.str;
      default = "rw,nohide,insecure,no_subtree_check,no_root_squash";
      description = "Export options applied to each exported directory";
    };

    extraExports = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra raw export lines to append to services.nfs.server.exports";
    };
  };
}
