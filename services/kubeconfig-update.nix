{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.imports = [
    ../home-manager/services/kubeconfig-update.nix
  ];
}
