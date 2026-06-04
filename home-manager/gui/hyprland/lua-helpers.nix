# Helpers for building Hyprland Lua `settings` entries (configType = "lua").
#
# Under the lua renderer, `settings.<name>` becomes an `hl.<name>(...)` call and
# `{ _args = [ ... ]; }` produces a multi-argument call. Dispatchers are Lua
# expressions, so they must be wrapped in `mkLuaInline`. These helpers keep the
# bind tables readable.
{ lib }:
let
  inherit (lib.generators) mkLuaInline;
in
rec {
  # Lua expression for an exec_cmd dispatcher (cmd is run through the shell).
  exec = cmd: "hl.dsp.exec_cmd(${builtins.toJSON cmd})";

  # A bind entry: key combo + raw Lua dispatcher expression.
  bind = combo: disp: {
    _args = [
      combo
      (mkLuaInline disp)
    ];
  };

  # A bind entry with options, e.g. { locked = true; } / { repeating = true; }.
  bindOpts = combo: disp: opts: {
    _args = [
      combo
      (mkLuaInline disp)
      opts
    ];
  };

  # Convenience: bind a key combo to an exec_cmd dispatcher.
  execBind = combo: cmd: bind combo (exec cmd);
  execBindLocked = combo: cmd: bindOpts combo (exec cmd) { locked = true; };
}
