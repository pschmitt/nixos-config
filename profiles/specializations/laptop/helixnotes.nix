{ config, pkgs, ... }:
{
  home-manager.users.${config.mainUser.username}.home.packages = [ pkgs.master.helixnotes ];
}
