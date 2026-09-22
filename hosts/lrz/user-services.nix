{ config, lib, ... }:
{
  # FNUC-013: keep fnuc's automation authoritative during staging. In particular,
  # do not import hosts/fnuc/default.nix or copy its home/service identities.
  home-manager.users.${config.mainUser.username} = {
    imports = [
      ../../home-manager/ssh-clipboard-peers.nix
    ];

    services = {
      jcalapi.enable = lib.mkForce false;
      ssh-clipboard.headlessX11 = true;
      home-manager.autoUpgrade.enable = lib.mkForce false;
    };
  };
}
