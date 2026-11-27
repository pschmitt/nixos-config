{ config, ... }:
{
  home-manager.users.${config.mainUser.username} = {
    imports = [ ../../modules/home-manager/mickey.nix ];

    programs.mickey.enable = true;

    wayland.windowManager.hyprland.settings.device = [
      {
        name = "mickey-virtual-input";
        kb_layout = "gpdpocket4-de";
      }
    ];
  };
}
