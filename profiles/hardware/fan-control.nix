{ config, pkgs, ... }:
{
  # pschmitt/fan-control needs group-scoped write access to whichever fan
  # control interface is present, without running as root at runtime or
  # making it world-writable. Safe to apply on all three hosts unconditionally
  # (per AGENTS.md: no per-host branching in shared profiles) — a udev rule
  # for hardware that isn't present here is a no-op, and thinkpad_acpi's
  # fan_control module option is ignored when the module isn't loaded.
  # See plugins/fan-control/README.md in pschmitt/noctalia-plugins.
  users.groups.fan_ctl = { };
  users.users.${config.mainUser.username}.extraGroups = [ "fan_ctl" ];
  boot.extraModprobeConfig = ''
    options thinkpad_acpi fan_control=1
  '';
  services.udev.extraRules = ''
    ACTION=="add|bind", SUBSYSTEM=="platform", DRIVER=="thinkpad_acpi", RUN+="${pkgs.coreutils}/bin/chgrp fan_ctl /proc/acpi/ibm/fan", RUN+="${pkgs.coreutils}/bin/chmod 0664 /proc/acpi/ibm/fan"
    SUBSYSTEM=="hwmon", ATTR{name}=="dell_smm", RUN+="${pkgs.bash}/bin/sh -c 'for f in /sys/%p/pwm*; do ${pkgs.coreutils}/bin/chgrp fan_ctl \"$$f\"; ${pkgs.coreutils}/bin/chmod 0664 \"$$f\"; done'"
    SUBSYSTEM=="hwmon", ATTR{name}=="gpdfan", RUN+="${pkgs.bash}/bin/sh -c 'for f in /sys/%p/pwm*; do ${pkgs.coreutils}/bin/chgrp fan_ctl \"$$f\"; ${pkgs.coreutils}/bin/chmod 0664 \"$$f\"; done'"
  '';
}
