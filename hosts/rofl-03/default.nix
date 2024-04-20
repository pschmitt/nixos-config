{ pkgs, config, ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../common/global

    ../../misc/luks-ssh-unlock.nix
    ../../misc/git-clone-nixos-config.nix
    ../../misc/users/github-actions.nix
    ../../misc/users/nix-remote-builder.nix
  ];

  # Write logs to console
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];

  custom.useBIOS = true;

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

  environment.systemPackages = with pkgs; [
    git
  ];
}
