{ config, ... }:
{
  home-manager.users.${config.mainUser.username}.imports = [
    ../home-manager/services/codex-ha-bridge.nix
  ];
}
