{ config, ... }:
{
  # AccountService profile picture
  # see: common/global/users/pschmitt.nix
  home.file.".face" = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "/var/lib/AccountsService/icons/${config.home.username}";
  };
}
