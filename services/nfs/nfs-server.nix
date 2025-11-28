args@{ lib, ... }:
let
  allowedIps = args.allowedIps or "100.64.0.0/10"; # cg-nat, ie tailscale/netbird
  basePath = args.basePath or "/mnt/data";
  exportPath = args.exportPath or "/export";
  exports =
    args.exports or [
      "backups"
      "blobs"
      "books"
      "documents"
      "mnt"
      "srv"
      "tmp"
      # "videos" # lives on rofl-11
    ];
  exportOptions = args.exportOptions or "rw,nohide,insecure,no_subtree_check,no_root_squash";
in
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
