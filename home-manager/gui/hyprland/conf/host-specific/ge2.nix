_: {
  xdg.configFile."hypr/lua/host.lua".text = ''
    hl.on("hyprland.start", function()
        hl.exec_cmd("hyprctl dispatch moveworkspacetomonitor 1 desc:LG")
        hl.exec_cmd("hyprctl dispatch moveworkspacetomonitor 2 desc:Lenovo")
        hl.exec_cmd("hyprctl dispatch focusmonitor desc:LG")
        hl.exec_cmd("hyprctl dispatch workspace 1")
        hl.exec_cmd("zhj pulseaudio::mute-default-source")
    end)
  '';
}
