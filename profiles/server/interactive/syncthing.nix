# syncthing — shared interactive-server Syncthing configuration.
{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.imports = [ ./syncthing-home.nix ];
}
