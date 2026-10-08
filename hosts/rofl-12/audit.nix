{
  # rofl-12's clock jumped +33d and back on 2026-10-08 (see
  # profiles/specializations/server/monit-clock-watch.nix) and nothing logged
  # who set it. Record clock steps so the next one names the culprit; slewing
  # via adjtimex is left out because timesyncd does that all the time.
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      "-a always,exit -F arch=b64 -S clock_settime -S settimeofday -k time-change"
    ];
  };
}
