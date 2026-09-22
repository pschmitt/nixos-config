{ config, ... }:
{
  # Keep lrz integrated with NixOS Home Manager rather than importing fnuc's
  # standalone Home Manager entrypoint and its host identity settings.
  home-manager.users.${config.mainUser.username} = {
    imports = [
      ../../home-manager/ssh-clipboard-peers.nix
    ];

    services = {
      jcalapi.enable = true;
      ssh-clipboard.headlessX11 = true;
    };
  };
}
