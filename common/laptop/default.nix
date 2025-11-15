{ inputs, lib, ... }:
{
  imports = [
    inputs.hardware.nixosModules.common-pc-laptop

    ../../services/bitwarden.nix
    ../../services/nix-distributed-build.nix

    ../wifi.nix
    ./network.nix
    ./wireshark.nix
  ];

  # power-profiles-daemon conflicts with tlp
  # https://linrunner.de/tlp/faq/ppd.html
  services = {
    power-profiles-daemon.enable = lib.mkForce true;
    tlp.enable = lib.mkForce false;
  };

  # https://www.freedesktop.org/software/systemd/man/latest/logind.conf.html
  services.logind.settings.Login = {
    HandlePowerKey = lib.mkDefault "suspend"; # default is "poweroff"
    HandleLidSwitchExternalPower = lib.mkDefault "suspend";
  };
}
