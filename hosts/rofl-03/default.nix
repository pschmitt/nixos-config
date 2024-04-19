{ pkgs, ... }: {
  imports = [
    ./disk-config.nix
    ./luks-root.nix
    ./hardware-configuration.nix
    ../../common/global

    ./github-actions.nix
  ];

  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  xdg.portal.config.common.default = "*";

  # Write logs to console
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];

  # Enable networking
  networking = {
    hostName = "rofl-03";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
