{ lib, osConfig, ... }:
{
  xdg.configFile."hypr/lua/windowrules.lua".text = ''
    local pip       = { class = "^(firefox)$",            title = "^(Picture-in-Picture)$"    }
    local sharing   = { class = "^(firefox)$",            title = "^(.*Sharing Indicator)$"   }
    local xdph      = { class = "^(hyprland-share-picker)$" }
    local zoom      = { class = "^(zoom)$"               }
    local gcr       = { class = "^(gcr-prompter)$"       }
    local peeppee   = { class = "^.*(-peepee)$"          }
    local porn      = { title = "(?i).*porn.*"           }
    local bitwarden = { title = "(?i).*bitwarden.*"      }

    -- Firefox PiP: float + pin
    hl.window_rule({ match = pip,     float = true })
    hl.window_rule({ match = pip,     pin   = true })

    -- Firefox sharing indicator: never steal focus or trigger fullscreen
    hl.window_rule({ match = sharing, float          = true       })
    hl.window_rule({ match = sharing, suppress_event = "fullscreen" })
    hl.window_rule({ match = sharing, suppress_event = "maximize"   })

    -- XDG share picker + Zoom quirks
    hl.window_rule({ match = xdph, pin            = true        })
    hl.window_rule({ match = zoom, suppress_event = "fullscreen" })

    -- GNOME keyring prompt
    hl.window_rule({ match = gcr, pin           = true })
    hl.window_rule({ match = gcr, stay_focused  = true })
    hl.window_rule({ match = gcr, no_screen_share = true })

    -- Sensitive applications
    hl.window_rule({ match = { tag = "noscreenshare" }, no_screen_share = true })
    hl.window_rule({ match = peeppee,   no_screen_share = true })
    hl.window_rule({ match = porn,      no_screen_share = true })
    hl.window_rule({ match = bitwarden, no_screen_share = true })
  ''
  + lib.optionalString (osConfig.networking.hostName != "ge2") ''

    -- Place Firefox on workspace 2 by default (ge2 has a custom layout).
    hl.window_rule({ match = { class = "^(firefox)$" }, workspace = "2" })
  '';
}
