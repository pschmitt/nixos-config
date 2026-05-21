{ config, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    # customizations
    # custom gdm monitor config
    ./gdm.nix
    ./wacom.nix
    ../../common/work/elgato-stream-deck.nix
    ../../common/work/crowdstrike-falcon-sensor.nix

    ../../common/global
    ../../common/gui
    ../../common/laptop
    ../../services/restic
    ../../common/work

    ../../services/initrd-luks-ssh-unlock.nix
  ];

  hardware.cattle = false;
  initrd.wifi = {
    enable = true;
    interfaceName = "wlp0s20f3";
  };

  # don't go to sleep when lid is closed
  services.logind.settings.Login = {
    HandleLidSwitchExternalPower = lib.mkForce "ignore";
    HandleLidSwitch = lib.mkForce "ignore";
  };

  # Enable networking
  networking = {
    hostName = "ge2";
    # Disable the firewall altogether.
    firewall.enable = false;
  };

  # We are tight on space on ge2, /boot is only 512MB
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 5;
}
