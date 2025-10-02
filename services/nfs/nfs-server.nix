{
  lib,
  allowedIps ? "100.64.0.0/10", # cg-nat, ie tailscale/netbird
  basePath ? "/mnt/data",
  exportPath ? "/export",
  exports ? [
    "backups"
    "blobs"
    "books"
    "documents"
    "mnt"
    "srv"
    "tmp"
    # "videos" # lives on rofl-11
  ],
  exportOptions ? "rw,nohide,insecure,no_subtree_check",
  ...
}:
{
  fileSystems = builtins.listToAttrs (
    map (dir: {
      name = "${exportPath}/${dir}";
      value.device = "${basePath}/${dir}";
      value.options = [ "bind" ];
    }) exports
  );

  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    ${exportPath} ${allowedIps}(rw,fsid=0,no_subtree_check)
    ${lib.concatStringsSep "\n" (
      map (dir: "${exportPath}/${dir} ${allowedIps}(${exportOptions})") exports
    )}
  '';

  networking.firewall.allowedTCPPorts = [ 2049 ];
}
