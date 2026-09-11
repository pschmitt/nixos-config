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

      home.packages = [ pkgs.caffeine ];

      # Noctalia requires XDG_SESSION_ID to connect to logind's session lock monitor.
      # Because noctalia.service runs as a systemd user service outside of the session scope,
      # GetSessionByPID(getpid()) fails if XDG_SESSION_ID is not already in the service environment.
      #
      # Hyprland's ext-session-lock protocol has no graceful handoff: if
      # noctalia.service stops while it holds an active lock -- for *any*
      # reason, not just a nixos-rebuild/home-manager switch restarting it,
      # but also noctalia restarting itself after hot-reloading a changed
      # plugin file on disk (observed live, 2026-09-11: a concurrent edit to
      # an unrelated plugin's icon triggered exactly this) -- the compositor
      # sees the lock client vanish mid-lock and refuses to auto-unlock (by
      # design: a lock client dying is exactly how a malicious process would
      # try to bypass a lock), falling back to its own placeholder ("Oopsie
      # daisy, it looks like you locked your screen but the lockscreen app
      # died") which takes no password and otherwise needs a manual
      # `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'` to
      # dismiss. ExecStopPost/ExecStartPost bracket noctalia.service's own
      # stop/start lifecycle (unlike a home-manager activation hook, which
      # only ever sees a switch-triggered restart) so this is caught
      # whatever actually stopped and restarted the service: ExecStopPost
      # drops a timestamped marker whenever a seat0 session is locked as the
      # service goes down, and the next ExecStartPost -- as long as that
      # marker isn't old enough to be a stale leftover from an unrelated
      # login/reboot -- clears the crashed fallback and re-locks, so a
      # restart never silently leaves the machine unlocked.
      systemd.user.services.noctalia.Service = {
        ExecStart =
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

        ExecStopPost =
          let
            noctaliaCaptureLockState = pkgs.writeShellScript "noctalia-capture-lock-state" ''
              marker="''${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/lock-recovery-pending"
              mkdir -p "$(dirname "$marker")"
              locked=0
              while IFS= read -r sid; do
                [[ -z "$sid" ]] && continue
                if [[ "$(${pkgs.systemd}/bin/loginctl show-session "$sid" -p LockedHint --value 2>/dev/null)" == "yes" ]]; then
                  locked=1
                fi
              done < <(${pkgs.systemd}/bin/loginctl list-sessions --no-legend 2>/dev/null | ${pkgs.gawk}/bin/awk -v u="$USER" '$3 == u && $4 ~ /^seat/ {print $1}')
              if [[ "$locked" == 1 ]]; then
                ${pkgs.coreutils}/bin/date +%s > "$marker"
              else
                rm -f "$marker"
              fi
            '';
          in
          "${noctaliaCaptureLockState}";

        ExecStartPost =
          let
            noctaliaRecoverLockscreen = pkgs.writeShellScript "noctalia-recover-lockscreen" ''
              marker="''${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/lock-recovery-pending"
              [[ -f "$marker" ]] || exit 0
              markerEpoch="$(cat "$marker" 2>/dev/null || echo 0)"
              rm -f "$marker"
              age=$(( $(${pkgs.coreutils}/bin/date +%s) - markerEpoch ))
              # Stale beyond a normal restart window (noctalia's logind lock
              # monitor is observed live to come back up within ~1s) -- most
              # likely a leftover from an unrelated login or reboot, not a
              # restart-while-locked, so don't act on it.
              if (( age > 120 )); then
                exit 0
              fi
              # Give noctalia a moment to reconnect its logind session-lock
              # monitor before touching anything.
              sleep 1
              ${pkgs.hyprland}/bin/hyprctl --instance 0 eval "hl.clear_crashed_lockscreen()" >/dev/null 2>&1 || true
              while IFS= read -r sid; do
                [[ -z "$sid" ]] && continue
                ${pkgs.systemd}/bin/loginctl lock-session "$sid" >/dev/null 2>&1 || true
              done < <(${pkgs.systemd}/bin/loginctl list-sessions --no-legend 2>/dev/null | ${pkgs.gawk}/bin/awk -v u="$USER" '$3 == u && $4 ~ /^seat/ {print $1}')
              # hypridle's own ext-idle-notify-v1 subscription is observed
              # live to wedge across this same crash/restart (confirmed
              # 2026-09-11: no `Idled:` timeout fired for 45+ minutes
              # afterwards despite zero HID activity on the USB
              # keyboard/touchpad IRQ counters) -- hypridle itself never
              # restarts on its own here, so its idle timer silently stops
              # advancing and the screen never re-locks on inactivity.
              # Restarting it re-establishes the subscription.
              ${pkgs.systemd}/bin/systemctl --user restart hypridle.service >/dev/null 2>&1 || true
            '';
          in
          "${noctaliaRecoverLockscreen}";
      };
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
