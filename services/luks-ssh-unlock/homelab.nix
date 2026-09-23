{ config, lib, ... }:
{
  imports = [ ./luks-ssh-unlock-fleet.nix ];

  # rofl-10 only needs to unlock the two hosts in the home lab.
  services.luks-ssh-unlock-fleet = {
    targetNames = [
      "fnuc"
      "lrz"
    ];
    jumpHost = {
      hostname = "turris.${config.domains.vpn}";
      username = "root";
      key = "/etc/ssh/ssh_host_ed25519_key";
    };
  };

  # The checksum helper opens its own SSH session and cannot use jumpHost.
  # Keep target host-key pinning enabled while skipping that direct session.
  services.luks-ssh-unlock.instances = {
    fnuc.initrdCheck.enable = lib.mkForce false;
    lrz.initrdCheck.enable = lib.mkForce false;
  };
}
