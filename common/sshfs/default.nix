{ inputs, outputs, lib, config, pkgs, ... }:
let
  opts = [
      "noauto"
      "_netdev"
      "allow_other"
      "reconnect"
      "follow_symlinks"
      "x-systemd.automount"
      # "x-gvfs-hide"
      "IdentityFile=${config.custom.homeDirectory}/.ssh/id_ed25519"
      "StrictHostKeyChecking=no"
      "UserKnownHostsFile=/dev/null"
      "ServerAliveInterval=10"
    ];

in {
  # NOTE Arch Linux equivalent /etc/fstab entry:
  # root@hass-fnuc.lan:/config  /mnt/hass-fnuc   fuse.sshfs    defaults,_netdev,noauto,x-systemd.automount,allow_other,reconnect,UserKnownHostsFile=/dev/null,StrictHostKeyChecking=no,IdentityFile=/home/pschmitt/.ssh/id_ed25519    0  0

  programs.fuse.userAllowOther = true;

  # https://releases.nixos.org/nix-dev/2016-September/021768.html
  fileSystems."/mnt/hass" = {
    fsType = "fuse";
    # NOTE We cannot use /config here since it is a symlink to /homeassistant
    device = "${pkgs.sshfs-fuse}/bin/sshfs#root@hass-fnuc.schmitt.co.beta.tailscale.net:/homeassistant";
    options = opts;
  };

  fileSystems."/mnt/turris" = {
    fsType = "fuse";
    device = "${pkgs.sshfs-fuse}/bin/sshfs#root@turris.schmitt.co.beta.tailscale.net:/";
    options = opts;
  };

  fileSystems."/mnt/rofl" = {
    fsType = "fuse";
    device = "${pkgs.sshfs-fuse}/bin/sshfs#ubuntu@rofl-01.schmitt.co.beta.tailscale.net:/mnt/data";
    options = opts;
  };
}
