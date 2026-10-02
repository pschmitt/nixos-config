# Keep fnuc reachable and the Home Assistant VM running when something
# runaway (agents, `nix eval`, nixos-upgrade evaluation) eats all memory.
# Without this, the host thrashes page cache until even sshd stops responding,
# while the kernel OOM killer never fires.
{
  # Compressed swap: gives the kernel somewhere to put cold anonymous pages
  # instead of evicting program text, and enables systemd-oomd swap tracking.
  zramSwap = {
    enable = true;
    memoryPercent = 25;
    priority = 100;
  };

  systemd = {
    # Home Assistant VM (8G guest RAM + qemu overhead): never reclaimed or
    # swapped out, and wins any CPU/IO contention. qemu itself already runs
    # with oom_score_adj -999 (inherited from libvirtd).
    slices.machine.sliceConfig = {
      MemoryMin = "9G";
      CPUWeight = 1000;
      IOWeight = 1000;
    };

    # Interactive sessions, AI agents and `nix eval` live here. Throttle,
    # then cap, then let systemd-oomd kill the offending session cgroup when
    # it stalls on memory for 30s.
    slices.user.sliceConfig = {
      MemoryHigh = "12G";
      MemoryMax = "16G";
      CPUWeight = 50;
      IOWeight = 50;
      ManagedOOMMemoryPressure = "kill";
      ManagedOOMMemoryPressureLimit = "50%";
    };

    services = {
      # Stay reachable to kill whatever went wrong.
      sshd.serviceConfig = {
        MemoryMin = "64M";
        CPUWeight = 1000;
        IOWeight = 1000;
        OOMScoreAdjust = -1000;
      };

      # Flake evaluation runs locally as root (builds are offloaded), and
      # peaks at several GB.
      nixos-upgrade.serviceConfig = {
        MemoryHigh = "8G";
        MemoryMax = "12G";
        CPUWeight = 20;
        IOWeight = 20;
        ManagedOOMMemoryPressure = "kill";
        ManagedOOMMemoryPressureLimit = "50%";
      };
    };
  };
}
