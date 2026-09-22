{ config, pkgs, ... }:
let
  agyWarmup = pkgs.writeShellApplication {
    name = "agy-warmup";
    runtimeInputs = [
      config.programs.antigravity-cli.package
      pkgs.coreutils
      pkgs.findutils
    ];
    text = builtins.readFile ./scripts/agy-warmup.sh;
  };
in
{
  home.packages = [ agyWarmup ];

  # Runs an agy query for Gemini and Claude/GPT models to keep the 5h usage
  # windows warm; the response and /usage quotas land in the journal.
  systemd.user.services.agy-warmup = {
    Unit.Description = "Start an agy session to keep the 5h usage window warm";
    Service = {
      Type = "oneshot";
      ExecStart = "${agyWarmup}/bin/agy-warmup";
    };
  };

  systemd.user.timers.agy-warmup = {
    Unit.Description = "Start an agy session at 04:00/09:00/14:00/19:00/23:00";
    Timer = {
      OnCalendar = "*-*-* 04,09,14,19,23:00:00";
      RandomizedDelaySec = "2min";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
