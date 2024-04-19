{ pkgs, ... }: {
  imports = [
    ./disk-config.nix
    ./luks-root.nix
    ./luks-data.nix
    ./hardware-configuration.nix
    ../../common/global
    ../../misc/git-clone-nixos-config.nix
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
    hostName = "rofl-02";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
