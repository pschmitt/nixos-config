{ config, pkgs, ... }:
let
  opts = [
    "noauto"
    "_netdev"
    "allow_other"
    "reconnect"
    "follow_symlinks"
    "x-systemd.automount"
    # https://www.freedesktop.org/software/systemd/man/latest/systemd.automount.html
    "x-systemd.device-timeout=10s"
    "x-systemd.mount-timeout=10s"
    # "x-gvfs-hide"
    "IdentityFile=${config.mainUser.homeDirectory}/.ssh/id_ed25519"
    "StrictHostKeyChecking=no"
    "UserKnownHostsFile=/dev/null"
    "ServerAliveInterval=10"
  ];

  vpnDomain = config.domains.vpn;
in
{
  # NOTE Arch Linux equivalent /etc/fstab entry:
  # root@hass-fnuc.lan:/config  /mnt/hass-fnuc   fuse.sshfs    defaults,_netdev,noauto,x-systemd.automount,allow_other,reconnect,UserKnownHostsFile=/dev/null,StrictHostKeyChecking=no,IdentityFile=/home/pschmitt/.ssh/id_ed25519    0  0

  programs.fuse.userAllowOther = true;

  # https://releases.nixos.org/nix-dev/2016-September/021768.html
  fileSystems = {
    "/mnt/fnuc" = {
      fsType = "fuse";
      device = "${pkgs.sshfs-fuse}/bin/sshfs#root@fnuc.${vpnDomain}:/";
      options = opts;
    };

    "/mnt/hass" = {
      fsType = "fuse";
      # NOTE We cannot use /config here since it is a symlink to /homeassistant
      device = "${pkgs.sshfs-fuse}/bin/sshfs#root@hass.${vpnDomain}:/homeassistant";
      options = opts;
    };

    "/mnt/hass-dieppe" = {
      fsType = "fuse";
      # NOTE We cannot use /config here since it is a symlink to /homeassistant
      device = "${pkgs.sshfs-fuse}/bin/sshfs#root@homeassistant-dieppe.${vpnDomain}:/homeassistant";
      options = opts;
    };

    "/mnt/oci-01" = {
      fsType = "fuse";
      device = "${pkgs.sshfs-fuse}/bin/sshfs#root@oci-01.${vpnDomain}:/";
      options = opts;
    };

    "/mnt/turris" = {
      fsType = "fuse";
      device = "${pkgs.sshfs-fuse}/bin/sshfs#root@turris.${vpnDomain}:/";
      options = opts;
    };

    # "/mnt/wrt1900ac" = {
    #   fsType = "fuse";
    #   device = "${pkgs.sshfs-fuse}/bin/sshfs#root@wrt1900ac.${vpnDomain}:/";
    #   options = opts;
    # };

    "/mnt/rofl-10" = {
      fsType = "fuse";
      device = "${pkgs.sshfs-fuse}/bin/sshfs#pschmitt@rofl-10.${vpnDomain}:/mnt/data";
      options = opts;
    };

    "/mnt/rofl-11" = {
      fsType = "fuse";
      device = "${pkgs.sshfs-fuse}/bin/sshfs#pschmitt@rofl-11.${vpnDomain}:/mnt/data";
      options = opts;
    };
  };
}
