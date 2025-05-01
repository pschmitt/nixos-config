{ lib, ... }:
let
  basePath = "/mnt/data";
  exportPath = "/export";
  subDirs = [
    "backups"
    "blobs"
    "books"
    "documents"
    "mnt"
    "srv"
    "tmp"
    # "videos" # lives on rofl-07 now
  ];
  nfsNetwork = "100.64.0.0/10";
  exportOptions = "rw,nohide,insecure,no_subtree_check";
in
{
  fileSystems = builtins.listToAttrs (
    map (dir: {
      name = "${exportPath}/${dir}";
      value.device = "${basePath}/${dir}";
      value.options = [ "bind" ];
    }) subDirs
  );

  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    ${exportPath} ${nfsNetwork}(rw,fsid=0,no_subtree_check)
    ${lib.concatStringsSep "\n" (
      map (dir: "${exportPath}/${dir} ${nfsNetwork}(${exportOptions})") subDirs
    )}
  '';

  networking.firewall.allowedTCPPorts = [ 2049 ];
}
