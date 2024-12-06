{ pkgs, ... }:
let
  libratbagPkg = pkgs.master.libratbag;
  piperPkg = pkgs.master.piper;
in
{
  # Logitech mouse settings
  services.ratbagd = {
    enable = true;
    package = libratbagPkg;
  };

  services.udev.extraRules = ''
    ACTION=="bind", SUBSYSTEM=="hid", ENV{HID_NAME}=="MX Master 3S", \
    RUN+="${libratbagPkg}/bin/ratbagctl 'MX Master 3S' dpi set 3000"
    ACTION=="bind", SUBSYSTEM=="hid", ENV{HID_NAME}=="Logitech MX Vertical Advanced Ergonomic Mouse", \
    RUN+="${libratbagPkg}/bin/ratbagctl 'MX Vertical' dpi set 3000"
  '';

  environment.systemPackages = [
    piperPkg
  ];
}
