{ lib, pkgs, inputs, ... }: {
  imports = [
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-gpu-amd
    # inputs.hardware.nixosModules.common-pc-ssd

    ./disk-config.nix
    ./hardware-configuration.nix
    ../../common/global
  ];

  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "*";

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
