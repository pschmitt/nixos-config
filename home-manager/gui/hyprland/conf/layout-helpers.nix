{ lib }:
let
  inherit (lib.generators) mkLuaInline;
in
rec {
  # Generate a top-level Lua snippet (suitable for extraConfig) that registers
  # a window.open subscriber immediately at config-parse time — not nested
  # inside hyprland.start. This avoids a race where XDG autostart windows may
  # open before the hyprland.start event fires.
  #
  # rules: [{ class = "firefox"; workspace = 2; refocus = 1; }]
  #   class     -- window class to match
  #   workspace -- target workspace number
  #   refocus   -- workspace to focus after move (optional)
  #
  # timeoutMs: remove the subscriber after this many ms (default: 60 000)
  #
  # Returns a plain Lua string for use in extraConfig.
  mkStartupLayoutLua =
    {
      rules,
      timeoutMs ? 60000,
      debug ? false,
    }:
    let
      ruleToLua =
        r:
        let
          refocusField = lib.optionalString (r.refocus or null != null) ", refocus = ${toString r.refocus}";
        in
        "{ class = \"${r.class}\", workspace = ${toString r.workspace}${refocusField} }";
      rulesLua = lib.concatMapStringsSep ",\n        " ruleToLua rules;
    in
    ''
      do
          local _debug = ${if debug then "true" else "false"}
          local _logPath = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hyprland-startup-layout.log"
          local _sequence = 0
          local function _log(message)
              if not _debug then return end
              local file = io.open(_logPath, "a")
              if file then
                  file:write(os.date("%Y-%m-%dT%H:%M:%S"), " ", message, "\n")
                  file:close()
              end
          end
          _log("listener-register")
          local _rules = {
              ${rulesLua},
          }
          local _sub
          _sub = hl.on("window.open", function(w)
              if not w then return end
              _sequence = _sequence + 1
              local eventId = _sequence
              local cls = w.class or ""
              local initialWorkspace = w.workspace and tostring(w.workspace.id) or "none"
              _log("event id=" .. eventId .. " class=" .. cls .. " workspace=" .. initialWorkspace)
              hl.timer(function()
                  for _, rule in ipairs(_rules) do
                      if cls == rule.class then
                          local beforeWorkspace = w.workspace and tostring(w.workspace.id) or "none"
                          if not w.workspace or w.workspace.id ~= rule.workspace then
                              local ok, err = pcall(function()
                                  hl.dispatch(hl.dsp.window.move({ workspace = rule.workspace, window = w }))
                              end)
                              local afterWorkspace = w.workspace and tostring(w.workspace.id) or "none"
                              _log("move id=" .. eventId .. " class=" .. cls .. " from=" .. beforeWorkspace .. " target=" .. rule.workspace .. " to=" .. afterWorkspace .. " dispatch=" .. tostring(ok) .. (ok and "" or " error=" .. tostring(err)))
                              if rule.refocus then
                                  hl.dispatch(hl.dsp.focus({ workspace = rule.refocus }))
                              end
                          else
                              _log("keep id=" .. eventId .. " class=" .. cls .. " workspace=" .. beforeWorkspace)
                          end
                          break
                      end
                  end
              end, { timeout = 100, type = "oneshot" })
          end)
          hl.timer(function()
              _log("listener-remove")
              _sub:remove()
          end, { timeout = ${toString timeoutMs}, type = "oneshot" })
      end
    '';

  # Legacy: wrap rules in a hyprland.start handler for the settings.on API.
  # Kept for reference; prefer using mkStartupLayoutLua + extraConfig.
  mkStartupLayout =
    {
      rules,
      timeoutMs ? 60000,
    }:
    mkLuaInline ''
      function()
          local rules = {
              ${
                lib.concatMapStringsSep ",\n            " (
                  r:
                  let
                    refocusField = lib.optionalString (r.refocus or null != null) ", refocus = ${toString r.refocus}";
                  in
                  "{ class = \"${r.class}\", workspace = ${toString r.workspace}${refocusField} }"
                ) rules
              },
          }
          local sub
          sub = hl.on("window.open", function(w)
              if not w then return end
              local cls = w.class or ""
              hl.timer(function()
                  for _, rule in ipairs(rules) do
                      if cls == rule.class then
                          if not w.workspace or w.workspace.id ~= rule.workspace then
                              hl.dispatch(hl.dsp.window.move({ workspace = rule.workspace, window = w }))
                              if rule.refocus then
                                  hl.dispatch(hl.dsp.focus({ workspace = rule.refocus }))
                              end
                          end
                          break
                      end
                  end
              end, { timeout = 100, type = "oneshot" })
          end)
          hl.timer(function() sub:remove() end, { timeout = ${toString timeoutMs}, type = "oneshot" })
      end
    '';
}
