{ config, ... }:
let
  cursorTheme = config.gtk.cursorTheme.name;
  cursorSize = "24";

  # KDE Plasma's "Wobbliness" slider (0 = less ... 4 = more), translated from
  # the KWin parameter sets (plugins/wobblywindows/wobblywindows.cpp): spring
  # frequency follows sqrt(stiffness), damping ratio follows
  # (1 - drag) / sqrt(stiffness), intensity follows the move factor.
  # Level 0 is the KDE default and matches the stiffness/damping we tuned by
  # hand (260/16).
  wobblinessLevel = 0;
  wobblinessPresets = [
    {
      stiffness = 260;
      damping = 17;
      intensity = 0.6;
    }
    {
      stiffness = 175;
      damping = 12.5;
      intensity = 0.6;
    }
    {
      stiffness = 105;
      damping = 8.5;
      intensity = 0.6;
    }
    {
      stiffness = 52;
      damping = 6.5;
      intensity = 1.2;
    }
    {
      stiffness = 17;
      damping = 2.5;
      intensity = 1.5;
    }
  ];
in
{
  # Decoration / animations / cursor + GTK glue.
  # Docs: https://wiki.hypr.land/Configuring/Variables/ and /Animations/
  wayland.windowManager.hyprland.settings = {
    # Cursor env vars (theme from gtk config, baked in at build time).
    env = [
      {
        _args = [
          "HYPRCURSOR_THEME"
          cursorTheme
        ];
      }
      {
        _args = [
          "HYPRCURSOR_SIZE"
          cursorSize
        ];
      }
      {
        _args = [
          "XCURSOR_THEME"
          cursorTheme
        ];
      }
      {
        _args = [
          "XCURSOR_SIZE"
          cursorSize
        ];
      }
    ];

    config = {
      decoration = {
        rounding = 2;
        dim_inactive = true;
        dim_strength = 0.1;
        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };
        blur = {
          enabled = false;
          size = 3;
          passes = 1;
          new_optimizations = true;
        };
        # Wobbly windows while moving/resizing (core since 0.57).
        wobble = {
          enabled = true;
          # KWin tessellates windows into a 20x20 grid.
          mesh = 20;
        }
        // builtins.elemAt wobblinessPresets wobblinessLevel;
      };

      group = {
        col = {
          border_active = "rgba(1e1e1eff)";
          border_inactive = "rgba(2a2a2aff)";
          border_locked_active = "rgba(1e1e1eff)";
          border_locked_inactive = "rgba(2a2a2aff)";
        };
        groupbar = {
          enabled = true;
          gradients = false;
          height = 14;
          indicator_height = 14;
          indicator_gap = 0;
          gaps_in = 0;
          gaps_out = 0;
          rounding = 0;
          col = {
            active = "rgba(1e1e1eff)";
            inactive = "rgba(2a2a2aff)";
            locked_active = "rgba(1e1e1eff)";
            locked_inactive = "rgba(2a2a2aff)";
          };
        };
      };

      animations.enabled = true;
    };

    # hl.curve("myBezier", { type = "bezier", points = { {0.05,0.9}, {0.1,1.05} } })
    curve = [
      {
        _args = [
          "myBezier"
          {
            type = "bezier";
            points = [
              [
                0.05
                0.9
              ]
              [
                0.1
                1.05
              ]
            ];
          }
        ];
      }
    ];

    # hl.animation({ leaf = ..., enabled = true, speed = ..., bezier = ... })
    animation = [
      {
        leaf = "windows";
        enabled = true;
        speed = 3;
        bezier = "myBezier";
      }
      {
        leaf = "windowsOut";
        enabled = true;
        speed = 3;
        bezier = "default";
        style = "popin 80%";
      }
      {
        leaf = "border";
        enabled = true;
        speed = 10;
        bezier = "default";
      }
      {
        leaf = "borderangle";
        enabled = true;
        speed = 8;
        bezier = "default";
      }
      {
        leaf = "fade";
        enabled = true;
        speed = 3;
        bezier = "default";
      }
      {
        leaf = "workspaces";
        enabled = true;
        speed = 2;
        bezier = "default";
      }
      {
        leaf = "layersIn";
        enabled = true;
        speed = 1.5;
        bezier = "default";
        style = "popin";
      }
    ];

    # Import GTK settings on every config load (hl.exec_cmd at parse time).
    exec_cmd = [ "${config.xdg.configHome}/sway/bin/import-gsettings.sh" ];
  };
}
