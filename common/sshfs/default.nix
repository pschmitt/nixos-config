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
    "IdentityFile=${config.custom.homeDirectory}/.ssh/id_ed25519"
    "StrictHostKeyChecking=no"
    "UserKnownHostsFile=/dev/null"
    "ServerAliveInterval=10"
  ];

  # tsDomain = "snake-eagle.ts.net";
  netbirdDomain = "nb.brkn.lol";
  vpnDomain = netbirdDomain;
in
{
  # NOTE Arch Linux equivalent /etc/fstab entry:
  # root@hass-fnuc.lan:/config  /mnt/hass-fnuc   fuse.sshfs    defaults,_netdev,noauto,x-systemd.automount,allow_other,reconnect,UserKnownHostsFile=/dev/null,StrictHostKeyChecking=no,IdentityFile=/home/pschmitt/.ssh/id_ed25519    0  0

  programs.fuse.userAllowOther = true;

  # https://releases.nixos.org/nix-dev/2016-September/021768.html
  fileSystems."/mnt/fnuc" = {
    fsType = "fuse";
    device = "${pkgs.sshfs-fuse}/bin/sshfs#root@fnuc.${vpnDomain}:/";
    options = opts;
  };

  fileSystems."/mnt/hass" = {
    fsType = "fuse";
    # NOTE We cannot use /config here since it is a symlink to /homeassistant
    device = "${pkgs.sshfs-fuse}/bin/sshfs#root@hass.${vpnDomain}:/homeassistant";
    options = opts;
  };

  fileSystems."/mnt/turris" = {
    fsType = "fuse";
    device = "${pkgs.sshfs-fuse}/bin/sshfs#root@turris.${vpnDomain}:/";
    options = opts;
  };

  # fileSystems."/mnt/wrt1900ac" = {
  #   fsType = "fuse";
  #   device = "${pkgs.sshfs-fuse}/bin/sshfs#root@wrt1900ac.${vpnDomain}:/";
  #   options = opts;
  # };

  fileSystems."/mnt/rofl-09" = {
    fsType = "fuse";
    device = "${pkgs.sshfs-fuse}/bin/sshfs#pschmitt@rofl-09.${vpnDomain}:/mnt/data";
    options = opts;
  };
}
