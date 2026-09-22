{
  systemd.services.nix-daemon.serviceConfig = {
    CPUWeight = 10;
    CPUQuota = "200%";
    IOWeight = 10;
    MemoryHigh = "4G";
    MemoryMax = "6G";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "40%";
    TasksMax = 4096;
  };
}
