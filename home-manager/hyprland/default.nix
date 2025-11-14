{
  config,
  osConfig ? null,
  ...
}:
let
  hostName = if osConfig == null then null else (osConfig.networking.hostName or null);
  wallpaperPath = "${config.home.homeDirectory}/Pictures/Wallpapers/chill.png";
in
{
  imports = [
    ./hyprdynamicmonitors.nix
    ./hyprgrass.nix
    ./hypridle.nix
    ./hyprlock.nix
    ../mako.nix
    ./bin
    ./env.nix
    ./swag.nix
    ./layouts.nix
    ./windowrules.nix
    ./input.nix
    ./keys.nix
    ./alt-tab.nix
    ./services.nix
    ./autostart.nix
    ./lock.nix
  ];

  wayland.windowManager.hyprland =
    let
      hostSpecificSettings =
        if hostName == "gk4" then
          {
            device = [
              {
                name = "hailuck-co.-ltd-usb-keyboard";
                kb_layout = "us,de";
              }
            ];

            input = {
              touchdevice = {
                enabled = true;
                output = "eDP-1";
                transform = 3;
              };
            };
          }
        else
          { };
    in
    {
      enable = true;
      settings = {
        "$config_dir" = "~/.config/hypr/config.d";
        "$bin_dir" = "~/.config/hypr/bin";
        "$sway_bin_dir" = "~/.config/sway/bin";
        "$ensure" = "$bin_dir/ensure-running.sh";
        "$ensure1" = "$ensure --single-instance";

        # Allow ad-hoc local overrides without nix rebuilds
        source = [
          "$config_dir/static.conf"
        ];

        debug = {
          disable_time = true;
          disable_logs = false;
          enable_stdout_logs = true;
        };

        general = {
          gaps_in = 0;
          gaps_out = 0;
          border_size = 2;
          "col.active_border" = "rgba(8aa4c5ff)";
          "col.inactive_border" = "rgba(595959ff)";
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
          disable_autoreload = true;
          enable_swallow = true;
          swallow_regex = "^(kitty)$";
          mouse_move_enables_dpms = true;
          key_press_enables_dpms = true;
          animate_manual_resizes = true;
          animate_mouse_windowdragging = true;
          focus_on_activate = false;
          new_window_takes_over_fullscreen = 2;
          exit_window_retains_fullscreen = true;
        };
      }
      // hostSpecificSettings;
    };

  services.hyprpaper = {
    enable = true;
    settings = {
      preload = [ wallpaperPath ];
      wallpaper = [ ",${wallpaperPath}" ];
    };
  };
}
