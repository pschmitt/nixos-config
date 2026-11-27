{ config, ... }:
{
  home-manager.users.${config.mainUser.username} = {
    imports = [ ../../home-manager/gui/mickey.nix ];

    wayland.windowManager.hyprland.settings.device = [
      {
        name = "mickey-virtual-input";
        kb_layout = "gpdpocket4-de";
      }
    ];
  };
}
