{ lib, pkgs, inputs, ... }: {
  imports = [
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-gpu-amd
    # inputs.hardware.nixosModules.common-pc-ssd

    ./disk-config.nix
    ./luks.nix
    ./hardware-configuration.nix
    ../../common/global
  ];

  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "*";

  # Write logs to console
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];

  # boot.loader.grub.device = "/dev/sda";
  # boot.loader.grub.efiSupport = false;
  # boot.loader.grub.efiInstallAsRemovable = false;
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # Enable networking
  networking = {
    hostName = "rofl-02";
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
