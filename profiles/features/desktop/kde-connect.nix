{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.services.kdeconnect = {
    enable = true;
    indicator = true;
  };
}

# vim: set ft=nix et ts=2 sw=2 :
