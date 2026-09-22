{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    # NOTE We cannot use /config here since it is a symlink to /homeassistant
    programs.fuse.userAllowOther = true;

    fileSystems."/mnt/ha" = {
      fsType = "fuse";
      device = "${pkgs.sshfs-fuse}/bin/sshfs#root@${config.services.home-assistant.sshfs.host}:/homeassistant";
      options = [
        "noauto"
        "_netdev"
        "allow_other"
        "reconnect"
        "follow_symlinks"
        "x-systemd.automount"
        # https://www.freedesktop.org/software/systemd/man/latest/systemd.automount.html
        "x-systemd.device-timeout=10s"
        "x-systemd.mount-timeout=10s"
        "IdentityFile=${config.services.home-assistant.sshfs.identityFile}"
        "IdentitiesOnly=yes"
        "StrictHostKeyChecking=no"
        "UserKnownHostsFile=/dev/null"
        "ServerAliveInterval=10"
      ];
    };
  };
}
