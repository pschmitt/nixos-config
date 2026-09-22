{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.imports = [
    ../home-manager/services/go-hass-agent.nix
  ];
}
