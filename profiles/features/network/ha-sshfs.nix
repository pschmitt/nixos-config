{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.custom.homeAssistant.sshfs.identityFile = lib.mkOption {
    type = lib.types.path;
    default = "${config.mainUser.homeDirectory}/.ssh/id_ed25519";
    description = ''
      SSH private key used to mount the Home Assistant config repo
      (/mnt/ha). Defaults to the main user's personal key (workstations);
      hosts without that key on disk (servers) should point this at a
      dedicated key instead.
    '';
  };

  options.custom.homeAssistant.sshfs.host = lib.mkOption {
    type = lib.types.str;
    default = "hass.${config.domains.vpn}";
    description = "SSH host serving the Home Assistant configuration mount.";
  };

  config = {
    # NOTE We cannot use /config here since it is a symlink to /homeassistant
    programs.fuse.userAllowOther = true;

    fileSystems."/mnt/ha" = {
      fsType = "fuse";
      device = "${pkgs.sshfs-fuse}/bin/sshfs#root@${config.custom.homeAssistant.sshfs.host}:/homeassistant";
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
        "IdentityFile=${config.custom.homeAssistant.sshfs.identityFile}"
        "IdentitiesOnly=yes"
        "StrictHostKeyChecking=no"
        "UserKnownHostsFile=/dev/null"
        "ServerAliveInterval=10"
      ];
    };
  };
}
