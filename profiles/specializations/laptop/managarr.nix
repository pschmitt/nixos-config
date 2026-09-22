{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.programs.managarr.enable = true;
}
