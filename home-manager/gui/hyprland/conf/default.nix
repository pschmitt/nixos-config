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

  wayland.windowManager.hyprland.enable = true;

  xdg.configFile."hypr/hyprland.lua".text = ''
    -- Entry point. Hyprland 0.55+ loads hyprland.lua in preference to hyprland.conf.
    -- Modules live in ~/.config/hypr/lua/.
    -- to read logs: journalctl -xlf --user -u 'wayland-wm@Hyprland.service'

    require("lua.settings")
    require("lua.env")
    require("lua.autostart")
    require("lua.input")
    require("lua.layouts")
    require("lua.swag")
    require("lua.windowrules")
    require("lua.lock")
    require("lua.keys")
    require("lua.plugins")
    require("lua.host")

    -- Dynamic monitor layout written by hyprdynamicmonitors (optional).
    pcall(require, "monitors")

    -- Optional local overrides without a rebuild: ~/.config/hypr/static.lua
    pcall(require, "static")
  '';

  xdg.configFile."hypr/lua/settings.lua".text = ''
    hl.config({
        debug = {
            disable_time       = true,
            disable_logs       = true,
            enable_stdout_logs = true,
        },

        general = {
            gaps_in          = 0,
            gaps_out         = 0,
            border_size      = 2,
            layout           = "dwindle",
            resize_on_border = true,
            col = {
                active_border   = "rgba(8aa4c5ff)",
                inactive_border = "rgba(595959ff)",
            },
            snap = { enabled = true },
        },

        binds = {
            workspace_back_and_forth = true,
            allow_workspace_cycles   = true,
        },

        misc = {
            disable_autoreload            = false,
            enable_swallow                = true,
            swallow_regex                 = "^(kitty)$",
            mouse_move_enables_dpms       = true,
            key_press_enables_dpms        = true,
            animate_manual_resizes        = true,
            animate_mouse_windowdragging  = true,
            focus_on_activate             = false,
            exit_window_retains_fullscreen = true,
        },
    })
  '';
}
