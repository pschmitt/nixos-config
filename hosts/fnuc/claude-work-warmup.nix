{ config, pkgs, ... }:
let
  # Same CLAUDE_CONFIG_DIR/ANTHROPIC_CONFIG_DIR defaulting as the "claude-work"
  # wrapper in home-manager/work/ai.nix, so this hits the same work profile.
  claudeWorkWarmupLaunch = pkgs.writeShellScript "claude-work-warmup-launch" ''
    export CLAUDE_CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-''${XDG_CONFIG_HOME:-$HOME/.config}/claude-work}"
    export ANTHROPIC_CONFIG_DIR="''${ANTHROPIC_CONFIG_DIR:-$CLAUDE_CONFIG_DIR}"

    # Pre-accept the workspace trust dialog for $HOME so the unattended tmux
    # session doesn't stall on the interactive "trust this folder?" prompt
    # (there's no CLI flag for this; it's tracked per-path in .claude.json).
    config_file="$CLAUDE_CONFIG_DIR/.claude.json"
    if [[ -f "$config_file" ]]
    then
      tmp_file="$(mktemp "$config_file.XXXXXX")"
      ${pkgs.jq}/bin/jq --arg path "$HOME" \
        '.projects[$path] = ((.projects[$path] // {}) + { hasTrustDialogAccepted: true })' \
        "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
    fi

    # --safe-mode disables plugins/MCP/hooks/etc, which avoids the separate
    # one-time "N new MCP servers found in this project" approval dialog that
    # plugin-provided MCP servers (e.g. browsermcp, home-assistant) trigger.
    # That dialog swallows the greeting keystrokes the same way the trust
    # dialog did, and this session has no use for any of those tools anyway.
    exec ${config.programs.claude-code.finalPackage}/bin/claude --model haiku --safe-mode
  '';

  claudeWorkWarmup = pkgs.writeShellApplication {
    name = "claude-work-warmup";
    runtimeInputs = [ pkgs.tmux ];
    text = ''
      CLAUDE_WORK_WARMUP_LAUNCH="${claudeWorkWarmupLaunch}"
      export CLAUDE_WORK_WARMUP_LAUNCH

      ${builtins.readFile ./scripts/claude-work-warmup.sh}
    '';
  };
in
{
  home.packages = [ claudeWorkWarmup ];

  # Starts a throwaway claude-work tmux session to keep the usage window
  # warm; the pane transcript (before and after the greeting, and after
  # /usage) lands in the journal for this service.
  systemd.user.services.claude-work-warmup = {
    Unit.Description = "Start a claude-work session to keep the 5h usage window warm";
    Service = {
      Type = "oneshot";
      ExecStart = "${claudeWorkWarmup}/bin/claude-work-warmup";
    };
  };

  systemd.user.timers.claude-work-warmup = {
    Unit.Description = "Start a claude-work session at 04:00/09:00/14:00/19:00/23:00";
    Timer = {
      OnCalendar = "*-*-* 04,09,14,19,23:00:00";
      RandomizedDelaySec = "2min";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
