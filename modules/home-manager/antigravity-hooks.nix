# agy reads all lifecycle hooks from one ~/.gemini/config/hooks.json, namespaced
# by tool. Let each module contribute its own namespace.
{ config, lib, ... }:
let
  cfg = config.programs.antigravity-cli;
in
{
  options.programs.antigravity-cli.hooks = lib.mkOption {
    type = lib.types.attrsOf lib.types.attrs;
    default = { };
    description = "Hook definitions per namespace, rendered to ~/.gemini/config/hooks.json.";
  };

  config.home.file.".gemini/config/hooks.json" = lib.mkIf (cfg.hooks != { }) {
    text = builtins.toJSON cfg.hooks;
  };
}
