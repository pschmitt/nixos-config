# tdarr-node — Tarr transcoding worker that also contributes spare CPU to the
# ***REMOVED*** proxy. Shared by the rofl-13 / rofl-14 compute nodes.
{ config, lib, ... }:
{
  imports = [
    ../services/harmonia.nix
    ../services/http.nix
    ../services/nfs/nfs-client-rofl-11.nix
    ../services/tdarr-node.nix

    (import ../services/***REMOVED***/***REMOVED***.nix {
      inherit config lib;
      useProxy = true;
      cpuUsage = 50;
    })
  ];
}
