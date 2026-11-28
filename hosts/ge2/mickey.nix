{ config, ... }:
{
  home-manager.users.${config.mainUser.username} = {
    imports = [ ../../modules/home-manager/mickey.nix ];

    programs.mickey = {
      enable = true;
      handoffAnimation = true;
      awayCursorIndicator = true;
      peers.gk4 = {
        address = "gk4.${config.domains.vpn}:4242";
        position = [
          5360
          240
        ];
      };
    };

    # The window border can meet Mickey's crossing edge.
    wayland.windowManager.hyprland.settings.config.general.hover_icon_on_border = false;

    wayland.windowManager.hyprland.settings.device = [
      {
        name = "mickey-virtual-input";
        kb_layout = "gpdpocket4-de";
      }
    ];
  };
}
