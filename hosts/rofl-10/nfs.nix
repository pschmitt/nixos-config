{ config, ... }:
{
  imports = [
    ../../services/nfs/nfs-server.nix
    ../../services/nfs/nfs-client.nix
  ];

  services.nfsExports = {
    enable = true;
    allowedIps = [ "100.64.0.0/10" ];
  };

  services.nfsMounts = {
    enable = true;
    server = "rofl-11.${config.domains.vpn}";
    exports = [
      "audiobooks"
      "books"
      "videos"
    ];
  };
}
