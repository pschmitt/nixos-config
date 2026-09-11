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
    (lib.mkIf config.programs.noctalia.enable {
      xdg.configFile."noctalia/config.toml".force = true;

      home = {
        packages = [ pkgs.caffeine ];

        # Noctalia requires XDG_SESSION_ID to connect to logind's session lock monitor.
        # Because noctalia.service runs as a systemd user service outside of the session scope,
        # GetSessionByPID(getpid()) fails if XDG_SESSION_ID is not already in the service environment.
        activation = {
          # Hyprland's ext-session-lock protocol has no graceful handoff: if
          # Noctalia (the session-lock client) is restarted -- e.g. by this
          # very activation's own reloadSystemd step, whenever a switch
          # changes anything noctalia.service depends on -- while it holds
          # an active lock, the compositor sees the client vanish mid-lock
          # and refuses to auto-unlock (by design: a lock client dying is
          # exactly how a malicious process would try to bypass a lock), so
          # it falls back to its own placeholder ("Oopsie daisy, it looks
          # like you locked your screen but the lockscreen app died") which
          # takes no password and needs a manual
          # `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'` to
          # dismiss -- confirmed live on gk4 (2026-09-11: a plugin crash
          # while locking hit the same failure path) and previously noticed
          # happening from an ordinary switch while stepped away with the
          # screen locked.
          #
          # These two activation entries bracket reloadSystemd (the DAG node
          # that actually restarts changed systemd --user units, see
          # home-manager's modules/systemd.nix) to detect exactly that case
          # -- noctalia.service demonstrably restarting (ActiveEnterTimestamp
          # advancing, not just "was locked before") while a seat0 session
          # had LockedHint=yes -- and only then clear the crashed fallback
          # and re-lock, so a switch never silently leaves the machine
          # unlocked. Gated on ActiveEnterTimestamp actually changing (not
          # merely "was locked") so this never touches a lock noctalia
          # didn't just drop.
          noctaliaCaptureLockState = lib.hm.dag.entryBefore [ "reloadSystemd" ] ''
            NOCTALIA_LOCK_RECOVERY_SESSIONS=""
            if command -v loginctl >/dev/null 2>&1; then
              while IFS= read -r sid; do
                [[ -z "$sid" ]] && continue
                if [[ "$(loginctl show-session "$sid" -p LockedHint --value 2>/dev/null)" == "yes" ]]; then
                  NOCTALIA_LOCK_RECOVERY_SESSIONS+="$sid "
                fi
              done < <(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$USER" '$3 == u && $4 ~ /^seat/ {print $1}')
            fi
            NOCTALIA_PRE_RESTART_TIMESTAMP=""
            if command -v systemctl >/dev/null 2>&1; then
              NOCTALIA_PRE_RESTART_TIMESTAMP=$(env XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" systemctl --user show noctalia.service -p ActiveEnterTimestamp --value 2>/dev/null || true)
            fi
            export NOCTALIA_LOCK_RECOVERY_SESSIONS NOCTALIA_PRE_RESTART_TIMESTAMP
          '';

          noctaliaRecoverLockscreen = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
            if [[ -n "''${NOCTALIA_LOCK_RECOVERY_SESSIONS:-}" ]] && command -v systemctl >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1
            then
              newTimestamp=$(env XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" systemctl --user show noctalia.service -p ActiveEnterTimestamp --value 2>/dev/null || true)
              if [[ -n "$newTimestamp" && "$newTimestamp" != "''${NOCTALIA_PRE_RESTART_TIMESTAMP:-}" ]]
              then
                warnEcho "Noctalia restarted while the session was locked -- clearing Hyprland's crashed-lockscreen fallback and re-locking"
                env XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" hyprctl --instance 0 eval "hl.clear_crashed_lockscreen()" >/dev/null 2>&1 || true
                for sid in ''${NOCTALIA_LOCK_RECOVERY_SESSIONS}
                do
                  env XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" loginctl lock-session "$sid" >/dev/null 2>&1 || true
                done
              fi
            fi
            unset NOCTALIA_LOCK_RECOVERY_SESSIONS NOCTALIA_PRE_RESTART_TIMESTAMP
          '';
        };
      };

      systemd.user.services.noctalia.Service.ExecStart =
        let
          noctaliaLauncher = pkgs.writeShellScript "noctalia-launcher" ''
            if [ -z "''${XDG_SESSION_ID:-}" ]; then
              XDG_SESSION_ID="$(${pkgs.systemd}/bin/loginctl list-sessions --no-legend 2>/dev/null | ${pkgs.gawk}/bin/awk -v u="$USER" '$3 == u && $4 ~ /^seat/ {print $1; exit}')"
              if [ -n "$XDG_SESSION_ID" ]; then
                export XDG_SESSION_ID
              fi
            fi
            exec ${config.programs.noctalia.package}/bin/noctalia "$@"
          '';
        in
        lib.mkForce "${noctaliaLauncher}";
    })

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
