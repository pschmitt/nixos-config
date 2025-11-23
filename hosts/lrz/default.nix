{ ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server

    # home-manager configuration (TEST!)
    ../../home-manager
    ../../common/gui/linger.nix
  ];

  custom.useBIOS = false;
  # NOTE avoids setting kernelParams that are only relevant for kvm guests
  # Having this set to true will cause the system to hang on boot and
  # you will *not* be able to enter the luks password on the console
  custom.kvmGuest = false;

  # Enable networking
  networking = {
    hostName = "lrz";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
