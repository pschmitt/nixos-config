_: {
  xdg.configFile."hypr/lua/host.lua".text = ''
    -- GPD Pocket 4 host-specific config.
    -- fake F1 (dead_circumflex) -> scratchpad terminal.
    -- NOTE: resolve_binds_by_sym = 1 would make this less keymap-dependent
    --       (bind "grave" instead of dead_circumflex).
    hl.bind("CTRL + dead_circumflex", hl.dsp.exec_cmd("~/.config/hypr/bin/scratchpad.sh term"))
    hl.bind("CTRL + escape",          hl.dsp.exec_cmd("~/.config/hypr/bin/scratchpad.sh term"))

    hl.config({
        input = {
            touchdevice = {
                enabled   = true,
                output    = "eDP-1",
                transform = 3,
            },
        },
    })
  '';
}
