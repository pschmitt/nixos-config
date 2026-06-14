{ config, ... }:
{
  imports = [
    (import ./nfs-client.nix {
      server = "rofl-11.${config.domains.netbird}";
      exports = [
        "audiobooks"
        "books"
        "videos"
      ];
      mountPoint = "/mnt/data";
    })
  ];
}
