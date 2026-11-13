{ config, ... }:
{
  # Keep lrz integrated with NixOS Home Manager rather than importing fnuc's
  # standalone Home Manager entrypoint and its host identity settings.
  home-manager.users.${config.mainUser.username}.services.jcalapi.enable = true;
}
