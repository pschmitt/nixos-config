{ config, ... }:
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
}
