{
  security = {
    auditd = {
      enable = true;
      settings = {
        max_log_file = 50;
        max_log_file_action = "ROTATE";
        num_logs = 10;
      };
    };

    audit = {
      enable = true;
      rules = [
        # Record kernel reboot requests. systemd may issue the syscall on behalf
        # of logind or an ACPI power event, so use the journal to identify the
        # original trigger; an out-of-band reset never reaches this syscall.
        "-a always,exit -F arch=b64 -S reboot -k system-reboot"
      ];
    };
  };

  # Keep logind and ACPI events available across boots for reboot attribution.
  services.journald.settings.Journal.Storage = "persistent";
}
