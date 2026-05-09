{ config, ... }:
let
  cursorTheme = config.gtk.cursorTheme.name;
  cursorSize = "24";
in
{
  xdg.configFile."hypr/lua/swag.lua".text = ''
    -- Cursor env vars (theme from gtk config, baked in at build time)
    hl.env("HYPRCURSOR_THEME", "${cursorTheme}")
    hl.env("HYPRCURSOR_SIZE",  "${cursorSize}")
    hl.env("XCURSOR_THEME",    "${cursorTheme}")
    hl.env("XCURSOR_SIZE",     "${cursorSize}")

    hl.config({
        decoration = {
            rounding      = 2,
            dim_inactive  = true,
            dim_strength  = 0.1,
            shadow = {
                enabled      = true,
                range        = 4,
                render_power = 3,
                color        = "rgba(1a1a1aee)",
            },
            blur = {
                enabled           = false,
                size              = 3,
                passes            = 1,
                new_optimizations = true,
            },
        },

        group = {
            col = {
                border_active        = "rgba(1e1e1eff)",
                border_inactive      = "rgba(2a2a2aff)",
                border_locked_active = "rgba(1e1e1eff)",
                border_locked_inactive = "rgba(2a2a2aff)",
            },
            groupbar = {
                enabled         = true,
                gradients       = false,
                height          = 14,
                indicator_height = 14,
                indicator_gap   = -14,
                gaps_in         = 0,
                gaps_out        = 0,
                rounding        = 0,
                col = {
                    active        = "rgba(1e1e1eff)",
                    inactive      = "rgba(2a2a2aff)",
                    locked_active = "rgba(1e1e1eff)",
                    locked_inactive = "rgba(2a2a2aff)",
                },
            },
        },

        animations = { enabled = true },
    })

    hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })

    hl.animation({ leaf = "windows",    enabled = true, speed = 3,   bezier = "myBezier" })
    hl.animation({ leaf = "windowsOut", enabled = true, speed = 3,   bezier = "default", style = "popin 80%" })
    hl.animation({ leaf = "border",     enabled = true, speed = 10,  bezier = "default" })
    hl.animation({ leaf = "borderangle", enabled = true, speed = 8,  bezier = "default" })
    hl.animation({ leaf = "fade",       enabled = true, speed = 3,   bezier = "default" })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 2,   bezier = "default" })
    hl.animation({ leaf = "layersIn",   enabled = true, speed = 1.5, bezier = "default", style = "popin" })

    -- Import GTK settings on every config load.
    hl.exec_cmd("~/.config/sway/bin/import-gsettings.sh")
  '';
}
