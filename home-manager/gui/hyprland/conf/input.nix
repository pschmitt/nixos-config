_: {
  xdg.configFile."hypr/lua/input.lua".text = ''
    local function hhkb(name)
        hl.device({ name = name, kb_layout = "hhkb-de,de,us" })
    end

    -- HHKB USB variants
    hhkb("pfu-limited-hhkb-hybrid")
    hhkb("pfu-limited-hhkb-hybrid-keyboard")
    hhkb("pfu-limited-hhkb-hybrid-consumer-control")

    -- HHKB Bluetooth slots
    hhkb("hhkb-hybrid_1-keyboard")
    hhkb("hhkb-hybrid_2-keyboard")
    hhkb("hhkb-hybrid_3-keyboard")
    hhkb("hhkb-hybrid_4-keyboard")

    hl.device({
        name         = "apple-inc.-magic-trackpad-usb-c",
        sensitivity  = 0.3,
        accel_profile = "adaptive",
        scroll_factor = 1.8,
    })

    -- GPD Pocket 4 keyboard and touchpad.
    -- NOTE: Relevant even on other hosts because of the KVM module.
    hl.device({ name = "hailuck-co.-ltd-usb-keyboard",       kb_layout = "gpdpocket4-de,gpdpocket4-us,us,de" })
    hl.device({ name = "hailuck-co.-ltd-usb-keyboard-mouse", natural_scroll = true })

    hl.config({
        input = {
            kb_layout  = "de,us",
            kb_variant = "",
            kb_model   = "",
            kb_options = "",
            kb_rules   = "",
            follow_mouse = 2,
            sensitivity  = 0,
            touchpad = { natural_scroll = false },
        },
        gestures = { workspace_swipe_invert = false },
    })

    hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace"               })
    hl.gesture({ fingers = 3, direction = "up",         action = "scale: 1.5, fullscreen"  })
    hl.gesture({ fingers = 3, direction = "down",       action = "scale: 1.5, fullscreen"  })
  '';
}
