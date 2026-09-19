{ config, lib, ... }:
{
  # FNUC-013: keep fnuc's automation authoritative during staging. In particular,
  # do not import hosts/fnuc/default.nix or copy its home/service identities.
  home-manager.users.${config.mainUser.username} = {
    services = {
      jcalapi.enable = lib.mkForce false;
      ssh-clipboard.enable = lib.mkForce false;
      syncthing.enable = lib.mkForce false;
      home-manager.autoUpgrade.enable = lib.mkForce false;
    };
  };
}
