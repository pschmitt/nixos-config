{ config, lib, ... }:
let
  cfg = config.services.nfsMounts;
in
{
  config = lib.mkIf cfg.enable {
    fileSystems = builtins.listToAttrs (
      map (dir: {
        name = "${cfg.mountPoint}/${dir}";
        value = {
          device = "${cfg.server}:${
            if toString cfg.exportPath == "/export" then "/${dir}" else "${cfg.exportPath}/${dir}"
          }";
          fsType = "nfs";
          options = [
            "noauto"
            "x-systemd.automount"
            "x-systemd.idle-timeout=600"
            "vers=4"
            "soft"
            "timeo=50"
            "retrans=3"
          ];
        };
      }) cfg.exports
    );
  };
}
