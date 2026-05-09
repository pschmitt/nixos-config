_: {
  xdg.configFile."hypr/lua/lock.lua".text = ''
    local lock = "~/.config/hypr/bin/lock.sh"

    hl.bind("SUPER + ALT + L", hl.dsp.exec_cmd(lock .. " --now"))

    -- locked = fires even when screen is locked
    hl.bind("SUPER + CTRL + ALT + L", hl.dsp.exec_cmd([[~/bin/zhj "lockscreen::restart"]]), { locked = true })
    hl.bind("switch:off:Lid Switch",  hl.dsp.exec_cmd(lock),                               { locked = true })
    hl.bind("switch:on:Lid Switch",   hl.dsp.dpms({ action = "on" }),                      { locked = true })

    hl.window_rule({ match = { class = "^(firefox)$" },     idle_inhibit = "fullscreen" })
    hl.window_rule({ match = { title = "^(Picture-in-Picture)$" }, idle_inhibit = "always" })
    hl.window_rule({ match = { class = "^(Google-chrome)$" }, idle_inhibit = "fullscreen" })
    hl.window_rule({ match = { class = "^(Chromium)$" },    idle_inhibit = "fullscreen" })
  '';
}
