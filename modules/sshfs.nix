{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.sshfs;
  mountOptions =
    mount:
    [
      "noauto"
      "_netdev"
      "allow_other"
      "reconnect"
      "follow_symlinks"
      "x-systemd.automount"
      "x-systemd.device-timeout=${mount.deviceTimeout}"
      "x-systemd.mount-timeout=${mount.mountTimeout}"
    ]
    ++ mount.extraOptions;

  mountOptionsModule = _args: {
    options = {
      host = lib.mkOption {
        type = lib.types.str;
        description = "SSH server to mount.";
      };

      mountPoint = lib.mkOption {
        type = lib.types.str;
        description = "Local mount point.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "/";
        description = "Remote path to mount.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "SSH user for the mount.";
      };

      deviceTimeout = lib.mkOption {
        type = lib.types.str;
        default = "10s";
        description = "Timeout for the mount device to become available.";
      };

      mountTimeout = lib.mkOption {
        type = lib.types.str;
        default = "10s";
        description = "Timeout for the mount operation.";
      };

      extraOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional SSHFS and SSH options.";
      };
    };
  };
in
{
  options.services.sshfs.mounts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule mountOptionsModule);
    default = { };
    description = "SSHFS filesystems managed by NixOS.";
  };

  config = lib.mkIf (cfg.mounts != { }) {
    environment.systemPackages = [ pkgs.sshfs-fuse ];
    programs.fuse.userAllowOther = true;

    fileSystems = lib.mapAttrs' (
      _name: mount:
      lib.nameValuePair mount.mountPoint {
        fsType = "fuse.sshfs";
        device = "${mount.user}@${mount.host}:${mount.path}";
        options = mountOptions mount;
      }
    ) cfg.mounts;
  };
}
