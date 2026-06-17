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

    # Base/global settings. Each top-level `settings` attr renders to an
    # hl.<name>(...) call in ~/.config/hypr/hyprland.lua.
    settings.config = {
      debug = {
        # to read logs: journalctl -xlf --user -u 'wayland-wm@Hyprland.service'
        disable_time = true;
        disable_logs = true;
        enable_stdout_logs = true;
      };

      general = {
        gaps_in = 0;
        gaps_out = 0;
        border_size = 2;
        layout = "dwindle";
        resize_on_border = true;
        col = {
          active_border = "rgba(8aa4c5ff)";
          inactive_border = "rgba(595959ff)";
        };
        snap.enabled = true;
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

    # Raw Lua appended to the generated hyprland.lua. Used for things the
    # `settings` renderer cannot express: making ~/.config/hypr require()able
    # and loading the optional dynamic-monitor / local-override modules.
    extraConfig = ''
      -- Allow require() of modules under ~/.config/hypr (e.g. monitors.lua).
      local cfg = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
      package.path = cfg .. "/hypr/?.lua;" .. package.path

      -- Load an optional module only if its file exists, so a missing file is
      -- not a config error; in-file errors are logged but do not abort the config.
      local function load_optional(name)
          local f = io.open(cfg .. "/hypr/" .. name .. ".lua", "r")
          if not f then
              return
          end
          f:close()
          local ok, err = pcall(require, name)
          if not ok then
              print("[hypr] error loading " .. name .. ".lua: " .. tostring(err))
          end
      end

      -- Dynamic monitor layout (optional, host-specific via xdg.configFile).
      load_optional("monitors")

      -- Ad-hoc local overrides without a rebuild: ~/.config/hypr/static.lua
      load_optional("static")
    '';
  };
}
