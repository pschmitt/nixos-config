{
  systemd.sleep.settings.Sleep.MemorySleepMode = "deep";

  services.upower = {
    criticalPowerAction = "PowerOff";
    percentageCritical = 10;
    percentageAction = 5;
  };
}
