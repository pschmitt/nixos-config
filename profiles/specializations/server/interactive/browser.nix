{ config, ... }:
{
  # Servers have no browser of their own: open URLs on the machine the user
  # is connected from.
  home-manager.users.${config.mainUser.username}.programs.ssh-client-browser.enable = true;
}
