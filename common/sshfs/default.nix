{ inputs, outputs, lib, config, pkgs, ... }: {
  # NOTE Arch Linux equivalent /etc/fstab entry:
  # root@hass-fnuc.lan:/config  /mnt/hass-fnuc   fuse.sshfs    defaults,_netdev,noauto,x-systemd.automount,allow_other,reconnect,UserKnownHostsFile=/dev/null,StrictHostKeyChecking=no,IdentityFile=/home/pschmitt/.ssh/id_ed25519    0  0
  fileSystems."/mnt/hass" = {
    fsType = "fuse";
    device = "${pkgs.sshfs-fuse}/bin/sshfs#root@hass-fnuc.schmitt.co.beta.tailscale.net:/config";
    options = [
      "noauto"
      "_netdev"
      "allow_other"
      "reconnect"
      "follow_symlinks"
      "x-systemd.automount"
      "IdentityFile=/home/pschmitt/.ssh/id_ed25519"
      "StrictHostKeyChecking=no"
      "UserKnownHostsFile=/dev/null"
      "ServerAliveInterval=10"
    ];
  };
}
