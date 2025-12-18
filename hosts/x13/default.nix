{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/global
    ../../common/gui
    ../../common/laptop
    ../../services/restic
    ../../common/work

    ../../services/nixos-installer-boot-entry.nix
  ];

  home-manager.users.${config.mainUser.username}.services.jellysync.enable = true;

  hardware = {
    cattle = false;
    fprintd.autoreset = {
      enable = true;
      deviceName = "Synaptics, Inc. Prometheus MIS Touch Fingerprint Reader";
    };
  };

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking = {
    hostName = "x13";
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
