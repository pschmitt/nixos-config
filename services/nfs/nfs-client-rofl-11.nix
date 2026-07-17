{ config, ... }:
let
  exports = [
    "audiobooks"
    "books"
    "videos"
  ];
in
{
  # services.nfsMounts models one server; laptops also mount media from rofl-11.
  fileSystems = builtins.listToAttrs (
    map (dir: {
      name = "/mnt/data/${dir}";
      value = {
        device = "rofl-11.${config.domains.netbird}:/export/${dir}";
        fsType = "nfs";
        options = [
          "noauto"
          "x-systemd.automount"
          "x-systemd.idle-timeout=600"
        ];
      };
    }) exports
  );
}
