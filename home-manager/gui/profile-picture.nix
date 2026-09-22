{ config, ... }:
{
  # AccountService profile picture
  # see: profiles/base/users/pschmitt.nix
  home.file.".face" = {
    enable = true;
    source = config.lib.file.mkOutOfStoreSymlink "/var/lib/AccountsService/icons/${config.home.username}";
  };
}
