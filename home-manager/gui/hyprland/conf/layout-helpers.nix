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
          local _rules = {
              ${rulesLua},
          }
          local _sub
          _sub = hl.on("window.open", function(w)
              if not w then return end
              local cls = w.class or ""
              hl.timer(function()
                  for _, rule in ipairs(_rules) do
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
          hl.timer(function() _sub:remove() end, { timeout = ${toString timeoutMs}, type = "oneshot" })
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
