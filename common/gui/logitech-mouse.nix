{ pkgs, ... }: {
  # Logitech mouse settings
  services.ratbagd.enable = true;

  services.udev.extraRules = ''
    ACTION=="bind", SUBSYSTEM=="hid", ENV{HID_NAME}=="MX Master 3S", \
    RUN+="${pkgs.libratbag}/bin/ratbagctl 'MX Master 3S' dpi set 3000"
    ACTION=="bind", SUBSYSTEM=="hid", ENV{HID_NAME}=="MX Vertical", \
    RUN+="${pkgs.libratbag}/bin/ratbagctl 'MX Vertical' dpi set 3000"
  '';
}
