# tdarr-node — Tdarr transcoding worker. Shared by the rofl-13 / rofl-14
# compute nodes.
{ config, ... }:
{
  imports = [
    ../services/harmonia.nix
    ../services/http.nix
    ../services/nfs/nfs-client.nix
    ../services/tdarr-node.nix
  ];

  services.nfsMounts = {
    enable = true;
    server = "rofl-11.${config.domains.netbird}";
    exports = [
      "audiobooks"
      "books"
      "videos"
    ];
  };
}
