{ config, lib, ... }:
let
  cfg = config.services.nfsExports;
in
{
  options.services.nfsExports = {
    enable = lib.mkEnableOption "NFS export server";

    allowedIps = lib.mkOption {
      type = lib.types.str;
      default = "100.64.0.0/10"; # cg-nat, ie tailscale/netbird
      description = "CIDR allowed to mount the NFS exports";
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
  };

  config = lib.mkIf cfg.enable {
    fileSystems = builtins.listToAttrs (
      map (dir: {
        name = "${cfg.exportPath}/${dir}";
        value = {
          device = "${cfg.basePath}/${dir}";
          fsType = "none";
          options = [ "bind" ];
        };
      }) cfg.exports
    );

    services.nfs.server.enable = true;
    services.nfs.server.exports = ''
      ${cfg.exportPath} ${cfg.allowedIps}(rw,fsid=0,no_subtree_check)
      ${lib.concatStringsSep "\n" (
        map (dir: "${cfg.exportPath}/${dir} ${cfg.allowedIps}(${cfg.exportOptions})") cfg.exports
      )}
    '';

    networking.firewall.allowedTCPPorts = [ 2049 ];
  };
}
