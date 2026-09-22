{
  imports = [
    # Offload compilation tasks to remote build machines (rofl-13, rofl-14, rofl-10).
    ../../../services/nix-distributed-build.nix
  ];

  # Disallow local builds on the homelab server (Intel NUC).
  # With max-jobs = 0, Nix will only fetch pre-built paths from binary caches
  # or dispatch derivations to remote builders over SSH. If neither is available,
  # the build fails fast rather than freezing the machine.
  nix.settings.max-jobs = 0;

  # Cgroup resource guardrails for nix-daemon. If a build is ever forced locally
  # (e.g. via `--max-jobs 2`) or during memory-heavy flake evaluations, these
  # limits keep the NUC responsive and prevent starvation of critical services
  # like Home Assistant.
  systemd.services.nix-daemon.serviceConfig = {
    # Lower CPU scheduling weight relative to default (100) so daemon yields to services.
    CPUWeight = 10;
    # Limit nix-daemon to at most 2 CPU cores (200% = 200% of a single core).
    CPUQuota = "200%";
    # Low I/O scheduling weight to avoid disk contention with running server workloads.
    IOWeight = 10;
    # Memory throttle threshold (4 GB) and hard cap (6 GB).
    MemoryHigh = "4G";
    MemoryMax = "6G";
    # Allow systemd-oomd to kill runaway Nix processes if memory pressure exceeds 40%.
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "40%";
    # Cap total process/thread count.
    TasksMax = 4096;
  };
}
