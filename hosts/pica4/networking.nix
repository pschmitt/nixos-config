{ config, ... }:
{
  networking = {
    firewall.enable = false;
    networkmanager = {
      dns = "systemd-resolved";
    };
    wireless = {
      userControlled = true;
    };
  };

  users.users."${config.mainUser.username}".extraGroups = [ "networkmanager" ];
}
