{ config, pkgs, ... }:
{
  home-manager.users.${config.mainUser.username}.services.lan-mouse = {
    enable = true;
    autoStart = false;
    # gk4's GPD Pocket 4 layout applies to Lan Mouse's virtual keyboard only.
    inputKeymapFile = "${pkgs.custom-keymaps}/share/keymaps/custom/gpdpocket4-de.xkb";
    peers = [
      {
        name = "gk4";
        position = "right";
      }
    ];
  };
}
