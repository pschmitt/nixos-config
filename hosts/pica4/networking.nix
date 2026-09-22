{ config, lib, ... }:
{
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    firewall.enable = false;
    networkmanager = {
      enable = true;
      dns = "systemd-resolved";
    };
    wireless = {
      enable = true;
      userControlled = true;
    };
  };

  users.users."${config.mainUser.username}".extraGroups = [ "networkmanager" ];
}
