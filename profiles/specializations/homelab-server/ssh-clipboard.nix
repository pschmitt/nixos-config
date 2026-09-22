{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.imports = [
    ../../../home-manager/ssh-clipboard-peers.nix
    ../../../home-manager/services/ssh-clipboard-headless.nix
  ];
}
