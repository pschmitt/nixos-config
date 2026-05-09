_: {
  xdg.configFile."hypr/lua/keys.lua".text = ''
    local bin      = "~/.config/hypr/bin"
    local swayBin  = "~/.config/sway/bin"
    local barify   = swayBin .. "/barify"
    local playerctl = swayBin .. "/playerctl-wrapper.sh"

    local brightUp   = barify .. " brightness up"
    local brightDown = barify .. " brightness down"
    local volUp      = barify .. " sink up"
    local volDown    = barify .. " sink down"
    local volMute    = barify .. " sink mute"

    local mouseSubmap  = "🖱️ mouse"
    local resizeSubmap = "↔️ resize"

    -- ── Core Hyprland management ───────────────────────────────────────────
    hl.bind("SUPER + SHIFT + C", hl.dsp.exec_cmd(bin .. "/kill-active.sh"))
    hl.bind("SUPER + SHIFT + K", hl.dsp.window.kill())
    hl.bind("SUPER + SHIFT + Q", hl.dsp.exec_cmd(bin .. "/leave.sh"))
    hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd(bin .. "/reload-config.sh"))

    -- ── Tiling / layout ───────────────────────────────────────────────────
    hl.bind("SUPER + SHIFT + space", hl.dsp.window.float({ action = "toggle" }))
    hl.bind("SUPER + ALT + space",   hl.dsp.layout("togglesplit"))
    hl.bind("SUPER + minus",         hl.dsp.layout("togglesplit"))
    hl.bind("SUPER + P",             hl.dsp.window.pseudo())
    hl.bind("SUPER + SHIFT + comma", hl.dsp.exec_cmd(bin .. "/switch-layout.sh"))
    hl.bind("SUPER + T",             hl.dsp.group.toggle())
    hl.bind("SUPER + SHIFT + T",     hl.dsp.group.move_window())
    hl.bind("SUPER + comma",         hl.dsp.group.next())

    -- ── Fullscreen ────────────────────────────────────────────────────────
    hl.bind("SUPER + F",         hl.dsp.window.fullscreen({ mode = 0 }))
    hl.bind("SUPER + M",         hl.dsp.window.fullscreen({ mode = 1 }))
    -- fullscreenstate: keep internal state, set client state to fake-fullscreen (2)
    hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen_state({ internal = -1, client = 2 }))

    -- ── Window movement ───────────────────────────────────────────────────
    hl.bind("SUPER + left",  hl.dsp.exec_cmd(bin .. "/move-window.sh l"))
    hl.bind("SUPER + right", hl.dsp.exec_cmd(bin .. "/move-window.sh r"))
    hl.bind("SUPER + up",    hl.dsp.exec_cmd(bin .. "/move-window.sh u"))
    hl.bind("SUPER + down",  hl.dsp.exec_cmd(bin .. "/move-window.sh d"))
    hl.bind("SUPER + s",     hl.dsp.window.swap({ next = true }))

    -- Move window to monitor and follow it
    hl.bind("SUPER + SHIFT + up",   hl.dsp.window.move({ monitor = "+1" }))
    hl.bind("SUPER + SHIFT + up",   hl.dsp.focus({ monitor = "+1" }))
    hl.bind("SUPER + SHIFT + up",   hl.dsp.cursor.move_to_corner({ corner = 4 }))
    hl.bind("SUPER + SHIFT + down", hl.dsp.window.move({ monitor = "-1" }))
    hl.bind("SUPER + SHIFT + down", hl.dsp.focus({ monitor = "-1" }))
    hl.bind("SUPER + SHIFT + down", hl.dsp.cursor.move_to_corner({ corner = 3 }))

    hl.bind("SUPER + SHIFT + left",  hl.dsp.window.move({ workspace = "e-1", silent = true }))
    hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ workspace = "e+1", silent = true }))

    -- ── Focus ─────────────────────────────────────────────────────────────
    hl.bind("SUPER + h", hl.dsp.focus({ direction = "left"  }))
    hl.bind("SUPER + l", hl.dsp.focus({ direction = "right" }))
    hl.bind("SUPER + k", hl.dsp.focus({ direction = "up"    }))
    hl.bind("SUPER + j", hl.dsp.focus({ direction = "down"  }))
    hl.bind("SUPER + SHIFT + tab", hl.dsp.exec_cmd(bin .. "/switch-workspace.sh previous"))
    hl.bind("SUPER + ALT + left",  hl.dsp.focus({ workspace = "-1" }))
    hl.bind("SUPER + ALT + right", hl.dsp.focus({ workspace = "+1" }))

    -- ── Workspace scroll (mouse wheel) ────────────────────────────────────
    hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
    hl.bind("SUPER + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

    -- ── Mouse drag / resize ───────────────────────────────────────────────
    hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true })
    hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

    -- ── Workspace switching (1–10, with moveworkspacetomonitor) ──────────
    local wkeys = {
        { "1", 1 }, { "2", 2 }, { "3", 3 }, { "4", 4 }, { "5", 5 },
        { "6", 6 }, { "7", 7 }, { "8", 8 }, { "9", 9 }, { "0", 10 },
    }
    for _, entry in ipairs(wkeys) do
        local key, ws = entry[1], entry[2]
        hl.bind("SUPER + " .. key, hl.dsp.exec_cmd("hyprctl dispatch moveworkspacetomonitor " .. ws .. " current"))
        hl.bind("SUPER + " .. key, hl.dsp.exec_cmd(bin .. "/switch-workspace.sh " .. ws))
        hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = ws }))
    end

    -- ── Resize (hold-to-repeat) ───────────────────────────────────────────
    hl.bind("SUPER + SHIFT + h", hl.dsp.window.resize({ direction = "left",  amount = 25 }), { repeating = true })
    hl.bind("SUPER + SHIFT + j", hl.dsp.window.resize({ direction = "down",  amount = 25 }), { repeating = true })
    hl.bind("SUPER + SHIFT + k", hl.dsp.window.resize({ direction = "up",    amount = 25 }), { repeating = true })
    hl.bind("SUPER + SHIFT + l", hl.dsp.window.resize({ direction = "right", amount = 25 }), { repeating = true })

    -- ── Applications ──────────────────────────────────────────────────────
    hl.bind("Print",               hl.dsp.exec_cmd(bin .. "/screenshot.sh"))
    hl.bind("SUPER + Return",      hl.dsp.exec_cmd(bin .. "/term.sh"))
    hl.bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd(bin .. "/term.sh"))
    hl.bind("SUPER + W",           hl.dsp.exec_cmd(bin .. "/run-or-raise.sh firefox"))
    hl.bind("SUPER + ALT + Y",     hl.dsp.exec_cmd(bin .. "/browser-run-or-raise.sh --title youtube --url https://www.youtube.com"))
    hl.bind("SUPER + ALT + Z",     hl.dsp.exec_cmd(bin .. "/ms-teams-join-room.sh home-room"))
    hl.bind("SUPER + ALT + T",     hl.dsp.exec_cmd(bin .. "/ms-teams-join-room.sh home-room"))
    hl.bind("SUPER + SHIFT + Z",   hl.dsp.exec_cmd([[zhj 'hyprctl::bring-window --fullscreen chrome']]))
    hl.bind("SUPER + ALT + H",     hl.dsp.exec_cmd(bin .. "/browser-run-or-raise.sh --url https://ha.brkn.lol --alt http://10.5.1.1:8123"))
    hl.bind("SUPER + ALT + numbersign", hl.dsp.exec_cmd(bin .. "/browser-rbw.sh"))  -- the '#' key
    hl.bind("F1",                  hl.dsp.exec_cmd(bin .. "/scratchpad.sh term"))
    hl.bind("SUPER + E",           hl.dsp.exec_cmd(bin .. "/scratchpad.sh files"))
    hl.bind("SUPER + SHIFT + V",   hl.dsp.exec_cmd(bin .. "/scratchpad.sh audio"))
    hl.bind("SUPER + ALT + a",     hl.dsp.exec_cmd("~/bin/obs.zsh alt"))
    hl.bind("SUPER + ALT + w",     hl.dsp.exec_cmd("~/bin/obs.zsh webcam"))
    hl.bind("SUPER + ALT + f",     hl.dsp.exec_cmd("~/bin/obs.zsh freeze"))
    hl.bind("SUPER + ALT + up",    hl.dsp.exec_cmd("~/bin/obs.zsh thumbs-up"))
    hl.bind("SUPER + ALT + down",  hl.dsp.exec_cmd("~/bin/obs.zsh thumbs-down"))
    hl.bind("SUPER + ALT + period", hl.dsp.exec_cmd("~/bin/obs.zsh emoji"))
    hl.bind("SUPER + R",           hl.dsp.exec_cmd("~/bin/wofi.zsh run"))
    hl.bind("SUPER + period",      hl.dsp.exec_cmd("~/bin/wofi.zsh emoji"))
    hl.bind("SUPER + ALT + c",     hl.dsp.exec_cmd("~/.config/waybar/custom_modules/clipboard.sh"))
    hl.bind("SUPER + ALT + v",     hl.dsp.exec_cmd("zhj clipboard::revert --notify"))
    hl.bind("SUPER + ALT + p",     hl.dsp.exec_cmd("~/bin/wofi.zsh bitwarden"))
    hl.bind("SUPER + ALT + m",     hl.dsp.exec_cmd("~/bin/wofi.zsh misc"))
    hl.bind("SUPER + ALT + j",     hl.dsp.exec_cmd("~/bin/wofi.zsh meetings"))
    hl.bind("SUPER + ALT + g",     hl.dsp.exec_cmd("~/bin/wofi.zsh bitwarden-work"))
    hl.bind("SUPER + ALT + s",     hl.dsp.exec_cmd("~/bin/wofi.zsh soundboard"))
    hl.bind("SUPER + SHIFT + s",   hl.dsp.exec_cmd("~/bin/wofi.zsh soundboard stop"))

    -- ── Mouse / hints / submap entry ──────────────────────────────────────
    hl.bind("SUPER + SHIFT + M",   hl.dsp.submap(mouseSubmap))
    hl.bind("SUPER + numbersign",  hl.dsp.exec_cmd("waypoint"))
    hl.bind("SUPER + SHIFT + H",   hl.dsp.exec_cmd("killall hints; hints"))
    hl.bind("SUPER + ALT + R",     hl.dsp.submap(resizeSubmap))

    -- ── Media / brightness (locked = works on lock screen) ────────────────
    hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(brightUp),   { locked = true })
    hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(brightDown), { locked = true })
    hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd(volUp),      { locked = true })
    hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd(volDown),    { locked = true })
    hl.bind("XF86AudioMute",         hl.dsp.exec_cmd(volMute),    { locked = true })
    hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("~/bin/obs.zsh toggle-mute"), { locked = true })
    hl.bind("SUPER + space",         hl.dsp.exec_cmd("~/bin/obs.zsh toggle-mute"), { locked = true })
    hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(playerctl .. " toggle"), { locked = true })
    hl.bind("XF86AudioPause", hl.dsp.exec_cmd(playerctl .. " pause"),  { locked = true })
    hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(playerctl .. " next"),   { locked = true })
    hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(playerctl .. " previous"), { locked = true })
    hl.bind("CTRL + ALT + up",    hl.dsp.exec_cmd(playerctl .. " toggle"),   { locked = true })
    hl.bind("CTRL + ALT + right", hl.dsp.exec_cmd(playerctl .. " next"),     { locked = true })
    hl.bind("CTRL + ALT + left",  hl.dsp.exec_cmd(playerctl .. " previous"), { locked = true })
    hl.bind("SUPER + ALT + b",    hl.dsp.exec_cmd("~/bin/obs.zsh brb --mute"), { locked = true })

    -- ── Submap: mouse mode ────────────────────────────────────────────────
    hl.define_submap(mouseSubmap, function()
        local function mv(args) return hl.dsp.exec_cmd("zhj mouse::move " .. args) end
        local function cl(btn)  return hl.dsp.exec_cmd("zhj mouse::click" .. (btn and (" " .. btn) or "")) end

        hl.bind("right", mv("+25"),    { repeating = true })
        hl.bind("left",  mv("-25"),    { repeating = true })
        hl.bind("up",    mv("-y -25"), { repeating = true })
        hl.bind("down",  mv("-y +25"), { repeating = true })
        hl.bind("SHIFT + right", mv("+50"),    { repeating = true })
        hl.bind("SHIFT + left",  mv("-50"),    { repeating = true })
        hl.bind("SHIFT + up",    mv("-y -50"), { repeating = true })
        hl.bind("SHIFT + down",  mv("-y +50"), { repeating = true })
        hl.bind("ALT + right", mv("+5"),   { repeating = true })
        hl.bind("ALT + left",  mv("-5"),   { repeating = true })
        hl.bind("ALT + up",    mv("-y -5"), { repeating = true })
        hl.bind("ALT + down",  mv("-y +5"), { repeating = true })

        hl.bind("return", cl(nil))
        hl.bind("space",  cl(nil))
        hl.bind("SHIFT + return", cl("right"))
        hl.bind("SHIFT + space",  cl("right"))
        hl.bind("ALT + return",   cl("middle"))
        hl.bind("ALT + space",    cl("middle"))

        local function mouseto(x, y) return hl.dsp.exec_cmd("dotoolc <<< 'mouseto " .. x .. " " .. y .. "'") end
        hl.bind("SHIFT + 0", mouseto("0",    "0"))
        hl.bind("SHIFT + 1", mouseto("1",    "0"))
        hl.bind("SHIFT + 2", mouseto("1",    "1"))
        hl.bind("SHIFT + 3", mouseto("0",    "1"))
        hl.bind("0",         mouseto("0.25", "0.25"))
        hl.bind("1",         mouseto("0.75", "0.25"))
        hl.bind("2",         mouseto("0.75", "0.75"))
        hl.bind("3",         mouseto("0.25", "0.75"))

        local function btn(action) return hl.dsp.exec_cmd("dotoolc <<< 'button" .. action .. " left'") end
        hl.bind("SUPER + SHIFT + space",  btn("down"))
        hl.bind("SUPER + SHIFT + return", btn("down"))
        hl.bind("SUPER + space",          btn("up"))
        hl.bind("SUPER + return",         btn("up"))

        hl.bind("escape", hl.dsp.submap("reset"))
        hl.bind("q",      hl.dsp.submap("reset"))
    end)

    -- ── Submap: resize mode ───────────────────────────────────────────────
    hl.define_submap(resizeSubmap, function()
        hl.bind("right", hl.dsp.window.resize({ direction = "right", amount = 25 }), { repeating = true })
        hl.bind("left",  hl.dsp.window.resize({ direction = "left",  amount = 25 }), { repeating = true })
        hl.bind("up",    hl.dsp.window.resize({ direction = "up",    amount = 25 }), { repeating = true })
        hl.bind("down",  hl.dsp.window.resize({ direction = "down",  amount = 25 }), { repeating = true })
        hl.bind("escape", hl.dsp.submap("reset"))
        hl.bind("return", hl.dsp.submap("reset"))
    end)
  '';
}
