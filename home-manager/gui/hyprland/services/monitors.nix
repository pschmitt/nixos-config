_: {
  xdg.configFile."hypr/monitors.lua".text = ''
    -- Dynamic monitor layout — classifies connected monitors by EDID
    -- description and reconfigures on every hotplug event.
    -- Works across all hosts; profiles are EDID-driven.

    -- Skip notifications during initial config load to avoid IPC deadlock.
    local _loaded = false

    local function notify(msg)
      if not _loaded then return end
      -- Background the call so Lua does not block on the IPC response.
      os.execute("hyprctl notify -1 5000 0 'fontsize:24 " .. msg .. "' &")
    end

    local function classify(monitors)
      local r = { laptop = nil, lenovo = nil, lg = nil, pikvm = nil, others = {} }
      for _, m in ipairs(monitors) do
        local d = m.description or ""
        if m.name == "eDP-1" then
          r.laptop = m
        elseif d:match("Lenovo.*M14") then
          r.lenovo = m
        elseif d:match("LG Electronics.*WQHD") then
          r.lg = m
        elseif d:match("PiKVM") or d:match("Synaptics Inc") then
          r.pikvm = m
        else
          table.insert(r.others, m)
        end
      end
      return r
    end

    local function reconfigure()
      local ms = classify(hl.get_monitors())
      local profile

      -- PiKVM is always disabled (KVM device, not a usable display)
      if ms.pikvm then
        hl.monitor({ output = ms.pikvm.name, disabled = true })
      end

      if ms.laptop and ms.lg and ms.lenovo then
        -- Triple-display stacked
        hl.monitor({ output = ms.laptop.name, mode = "1920x1200@48", position = "0x240",    scale = 1 })
        hl.monitor({ output = ms.lg.name,     mode = "3440x1440@59", position = "1920x0",   scale = 1 })
        hl.monitor({ output = ms.lenovo.name, mode = "1920x1080@60", position = "986x1440", scale = 1 })
        profile = "🖥️🖥️🖥️ Triple display"
      elseif ms.lg and ms.lenovo then
        -- Dual docked: LG primary, M14 to the left; laptop disabled if present
        hl.monitor({ output = ms.lg.name,     mode = "3440x1440@60", position = "0x0",     scale = 1 })
        hl.monitor({ output = ms.lenovo.name, mode = "1920x1080@60", position = "-1920x0", scale = 1 })
        if ms.laptop then
          hl.monitor({ output = ms.laptop.name, disabled = true })
        end
        profile = "🖥️🖥️ Dual docked"
      elseif ms.laptop and ms.lenovo then
        -- Laptop + M14
        hl.monitor({ output = ms.laptop.name, mode = "preferred", position = "0x0",        scale = 1.666, transform = 3 })
        hl.monitor({ output = ms.lenovo.name, mode = "preferred", position = "auto-right", scale = 1 })
        profile = "💻🖥️ Laptop + M14"
      elseif ms.laptop and ms.lg then
        -- Laptop + LG ultrawide
        hl.monitor({ output = ms.laptop.name, mode = "preferred",    position = "0x0",        scale = 1.666, transform = 3 })
        hl.monitor({ output = ms.lg.name,     mode = "3440x1440@60", position = "auto-right", scale = 1 })
        profile = "💻🖥️ Laptop + LG"
      elseif ms.laptop then
        -- Laptop only (extras, if any, placed below)
        hl.monitor({ output = ms.laptop.name, mode = "preferred", position = "auto", scale = 1.666, transform = 3 })
        profile = "💻 Laptop only"
      else
        -- Headless / unrecognised
        hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
        profile = "🔲 Fallback layout"
      end

      -- Unrecognised extras go to the right of whatever is already configured
      local n = #ms.others
      for _, m in ipairs(ms.others) do
        hl.monitor({ output = m.name, mode = "preferred", position = "auto-right", scale = 1 })
      end

      notify(profile .. (n > 0 and (" + " .. n .. " unknown") or ""))
    end

    reconfigure()
    _loaded = true
    hl.on("monitor.added",   reconfigure)
    hl.on("monitor.removed", reconfigure)
  '';
}
