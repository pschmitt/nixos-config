{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.services.jellysync.enable = true;
}
