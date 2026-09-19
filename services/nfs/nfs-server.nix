{ config, lib, ... }:
let
  cfg = config.services.nfsExports;
in
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

    services.nfs.server = {
      enable = true;

      # Keep the RPC mount daemon reachable through a host firewall. This is
      # also the port used by showmount and NFSv3 clients.
      mountdPort = 20048;
    };
    services.nfs.server.exports = ''
      ${cfg.exportPath} ${
        lib.concatStringsSep " " (map (ip: "${ip}(rw,fsid=0,no_subtree_check)") cfg.allowedIps)
      }
      ${lib.concatStringsSep "\n" (
        map (
          dir:
          "${cfg.exportPath}/${dir} ${
            lib.concatStringsSep " " (map (ip: "${ip}(${cfg.exportOptions})") cfg.allowedIps)
          }"
        ) cfg.exports
      )}
      ${cfg.extraExports}
    '';

    # rpcbind/mountd are needed for showmount and NFSv3. NFSv4 itself only
    # needs 2049, but exposing the same fixed RPC setup as the other NFS hosts
    # keeps diagnostics and older clients working too.
    networking.firewall.allowedTCPPorts = [
      111
      2049
      20048
    ];
    networking.firewall.allowedUDPPorts = [
      111
      20048
    ];

    # On a fresh installation nfs-mountd may start before exportfs has
    # created etab. Give it an empty state file so it stays running until
    # nfs-server populates the exports.
    systemd.tmpfiles.rules = [ "f /var/lib/nfs/etab 0644 root root -" ];
  };
}
