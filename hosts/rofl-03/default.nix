{ pkgs, ... }: {
  imports = [
    ./disk-config.nix
    ./luks-root.nix
    ./hardware-configuration.nix
    ../../common/global

    ../../misc/git-clone-nixos-config.nix
    ../../misc/github-actions.nix
  ];

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