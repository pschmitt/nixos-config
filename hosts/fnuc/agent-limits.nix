# Fence the coding agents in on fnuc. Idle codex sessions have repeatedly
# grown until user.slice hit its MemoryHigh (resource-control.nix), which
# throttles every user process into reclaim and swap: load ~48, all 15G of
# swap used, TBs re-read from disk, while systemd-oomd never picked a victim.
# Interactive codex runs in its own transient scope and Claude's remote-control
# server gets the same caps, so only the runaway session stalls or dies.
# Claude's remote-control server also gets restarted every night.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  limits = {
    MemoryHigh = "4G";
    MemoryMax = "6G";
    MemorySwapMax = "2G";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "50%";
  };

  remoteControlUnits = [
    "claude-remote-control.service"
  ];

  codex = pkgs.llm-agents.codex;

  codexScoped = pkgs.writeShellApplication {
    name = "codex";
    runtimeInputs = [ pkgs.systemd ];
    runtimeEnv = {
      CODEX_REAL = "${codex}/bin/codex";
      CODEX_SCOPE_PROPERTIES = toString (lib.mapAttrsToList (name: value: "${name}=${value}") limits);
    };
    text = builtins.readFile ./scripts/codex-scoped.sh;
  };

  # Same package as upstream (completions, version, meta), wrapped bin/codex.
  codexPackage = pkgs.symlinkJoin {
    inherit (codex) version meta;
    pname = "codex-scoped";
    paths = [ codex ];
    postBuild = ''
      rm "$out/bin/codex"
      ln -s ${codexScoped}/bin/codex "$out/bin/codex"
    '';
  };
in
{
  home-manager.users.${config.mainUser.username} = {
    programs.codex.package = lib.mkForce codexPackage;

    systemd.user.services = {
      claude-remote-control.Service = limits;

      # RuntimeMaxSec= would do for claude, but codex' unit is a oneshot
      # (RemainAfterExit) where it has no effect. A fixed nightly slot also
      # avoids cutting off a remote session during the day.
      agent-remote-control-restart = {
        Unit.Description = "Restart the agent remote-control servers";
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.systemd}/bin/systemctl --user try-restart ${toString remoteControlUnits}";
        };
      };
    };

    systemd.user.timers.agent-remote-control-restart = {
      Unit.Description = "Restart the agent remote-control servers nightly";
      Timer.OnCalendar = "*-*-* 04:30:00";
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
