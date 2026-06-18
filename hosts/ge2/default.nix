{ config, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    # customizations
    # custom gdm monitor config
    ./gdm.nix
    ./wacom.nix
    ../../profiles/work/elgato-stream-deck.nix
    ../../profiles/work/crowdstrike-falcon-sensor.nix

    ../../profiles/workstation.nix

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

  # ge2 uses UKIs with ~155 MB initrds, so /boot can only hold two
  # generations comfortably on its 512 MB EFI partition.
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 2;

  home-manager.users.${config.mainUser.username} = {
    services.go-hass-agent.enableWorkCommands = true;
  };
}
