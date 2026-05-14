{
  imports = [
    # ./alt-tab.nix
    ./autostart.nix
    ./env.nix
    ./host-specific.nix
    ./input.nix
    ./keys.nix
    ./layouts.nix
    ./lock.nix
    ./swag.nix
    ./windowrules.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "lua";
    importantPrefixes = [
      "config"
      "curve"
      "name"
      "output"
    ];

    settings = {
      config = {
        debug = {
          disable_time = true;
          # to read logs: journalctl -xlf --user -u 'wayland-wm@Hyprland.service'
          disable_logs = true;
          enable_stdout_logs = true;
        };

        general = {
          gaps_in = 0;
          gaps_out = 0;
          border_size = 2;
          col = {
            active_border = "rgba(8aa4c5ff)";
            inactive_border = "rgba(595959ff)";
          };
          layout = "dwindle";
          resize_on_border = true;
          snap = {
            enabled = true;
          };
        };

        binds = {
          workspace_back_and_forth = true;
          allow_workspace_cycles = true;
        };

        misc = {
          disable_autoreload = false;
          enable_swallow = true;
          swallow_regex = "^(kitty)$";
          mouse_move_enables_dpms = true;
          key_press_enables_dpms = true;
          animate_manual_resizes = true;
          animate_mouse_windowdragging = true;
          focus_on_activate = false;
          exit_window_retains_fullscreen = true;
        };
      };
    };
  };
}
