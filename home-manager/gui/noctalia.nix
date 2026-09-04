{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.noctalia;
in
{
  # Module import only: `programs.noctalia.enable` is opt-in per host (see
  # profiles/laptop/noctalia.nix), same as dank.nix.
  imports = [
    inputs.noctalia.homeModules.default
  ];

  options.custom.noctalia.resetStateOnActivation = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      On every activation, delete Noctalia's app-owned
      `settings.toml` (GUI/runtime overrides layered on top of our
      declarative `config.toml`) so it can't pin stale state across a
      rebuild — e.g. a local plugin's `[[plugins.source]]` entry stuck on
      the /nix/store path it was first seeded with, missing the
      charging-bolt icon after `noctalia-battery-icon` moved from 0.1.0
      to 0.2.5 (2026-09-04). Noctalia's own docs call this file "safe to
      delete when you want to clear those overrides", and it's
      hot-reloaded, so this self-heals without a service restart.

      This also discards anything set only through the Settings UI
      (tokens like the Home Assistant plugin's, dragged lockscreen-widget
      positions, live-tweaked plugin colors, etc.) on every switch — move
      that into `programs.noctalia.settings`/`plugin_settings` instead of
      relying on the GUI if you want it to survive.
    '';
  };

  config = lib.mkMerge [
    {
      # The upstream home module points `programs.noctalia.package` (via
      # `lib.mkDefault`) straight at `inputs.noctalia.packages.${system}.default`,
      # bypassing pkgs entirely -- so overlays/noctalia.nix's patched build
      # (see its comment for why: plugin-notification icon support) only
      # takes effect if we repoint it at `pkgs.noctalia` here.
      programs.noctalia.package = pkgs.noctalia;
    }
    (lib.mkIf (config.programs.noctalia.enable && cfg.resetStateOnActivation) {
      home.activation.noctaliaResetState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        state_file="${config.xdg.stateHome}/noctalia/settings.toml"
        if [[ -f "$state_file" ]]; then
          run rm -f "$state_file"
        fi
      '';
    })
  ];
}
