{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.programs.zsh = {
    sessionVariables = {
      NETWORK_LOCATION = "home";
      NO_LOCATION_UPDATE = "1";
      SERVER = "1";
    };
  };
}
