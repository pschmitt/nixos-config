{
  pkgs,
  ...
}:
let
  terminal = "kitty";
  launcher = "fuzzel";
  locker = "swaylock";
in
{
  home.packages = with pkgs; [
    kitty
    fuzzel
    swaylock
  ];

  xdg.configFile."niri/config.kdl".text = ''
    // Quick niri setup curated for experimentation.

    input {
        keyboard {
            xkb {
                layout "us"
                options "compose:ralt"
            }
            numlock
        }

        touchpad {
            tap
            natural-scroll
        }
    }

    layout {
        gaps 12
        focus-ring {
            width 3
            active-color "#89dceb"
            inactive-color "#45475a"
        }
        border {
            width 2
            active-color "#6c7086"
            inactive-color "#313244"
        }
    }

    binds {
        Mod+Return { spawn "${terminal}"; }
        Mod+D { spawn "${launcher}"; }
        Mod+Shift+Escape { spawn "${locker}"; }

        Mod+Q repeat=false { close-window; }
        Mod+Shift+Q { quit; }

        Mod+H { focus-column-left; }
        Mod+J { focus-window-down; }
        Mod+K { focus-window-up; }
        Mod+L { focus-column-right; }

        Mod+Ctrl+H { move-column-left; }
        Mod+Ctrl+J { move-window-down; }
        Mod+Ctrl+K { move-window-up; }
        Mod+Ctrl+L { move-column-right; }

        Mod+Shift+H { focus-monitor-left; }
        Mod+Shift+L { focus-monitor-right; }

        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+4 { focus-workspace 4; }
        Mod+5 { focus-workspace 5; }
        Mod+Ctrl+1 { move-column-to-workspace 1; }
        Mod+Ctrl+2 { move-column-to-workspace 2; }
        Mod+Ctrl+3 { move-column-to-workspace 3; }
        Mod+Ctrl+4 { move-column-to-workspace 4; }
        Mod+Ctrl+5 { move-column-to-workspace 5; }
    }
  '';

  # Make it easy to discover from shells.
  programs.zsh.shellAliases = {
    niri-msg = "niri msg";
  };
}
