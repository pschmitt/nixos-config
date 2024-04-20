{ pkgs, ... }: {
  imports = [
    ./disk-config.nix
    ./luks-root.nix
    ./luks-data.nix
    ./hardware-configuration.nix
    ../../common/global

    ../../misc/git-clone-nixos-config.nix
    ../../misc/users/github-actions.nix
    ../../misc/users/nix-remote-builder.nix
  ];

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

  services.harmonia = {
    enable = true;
    settings = {
      bind = "100.85.145.107:5000";
    };
  };
}
