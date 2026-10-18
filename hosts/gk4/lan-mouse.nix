{ config, pkgs, ... }:
{
  home-manager.users.${config.mainUser.username}.services.lan-mouse = {
    enable = true;
    autoStart = false;
    # ge2's HHKB layout applies to Lan Mouse's virtual keyboard only.
    inputKeymapFile = "${pkgs.custom-keymaps}/share/keymaps/custom/hhkb-de.xkb";
    peers = [
      {
        name = "ge2";
        position = "left";
      }
    ];
  };
}
