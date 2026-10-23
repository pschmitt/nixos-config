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
        # Record changes that can affect local accounts or privilege grants.
        "-w /etc/passwd -p wa -k identity"
        "-w /etc/group -p wa -k identity"
        "-w /etc/shadow -p wa -k identity"
        "-w /etc/sudoers -p wa -k scope"

        # Record direct system clock changes; routine clock slewing is excluded.
        "-a always,exit -F arch=b64 -S clock_settime -S settimeofday -k time-change"
      ];
    };
  };
}
