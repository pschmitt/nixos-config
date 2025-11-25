{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    # customizations
    # custom gdm monitor config
    ./gdm.nix
    ./wacom.nix
    ../../common/work/elgato-stream-deck.nix

    ../../common/global
    ../../common/gui
    ../../common/laptop
    ../../common/restic
    ../../common/work

    ../../misc/initrd-luks-ssh-unlock.nix
  ];

  custom.cattle = false;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  services.logind.settings.Login = {
    HandleLidSwitchExternalPower = lib.mkForce "ignore";
    HandleLidSwitch = lib.mkForce "ignore";
  };

  # Enable networking
  networking = {
    hostName = "ge2";
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
