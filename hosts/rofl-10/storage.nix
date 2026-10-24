{
  # Keep journal growth bounded on the small root filesystem.
  services.journald.settings.Journal = {
    Storage = "persistent";
    SystemMaxUse = "1G";
    SystemKeepFree = "5G";
  };
}
