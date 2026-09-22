{ config, lib, ... }:
let
  cfg = config.services.nfsExports;
in
{
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
