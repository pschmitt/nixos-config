{ ... }:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../common/server

    # home-manager configuration (TEST!)
    ../../common/gui/linger.nix
  ];

  hardware.biosBoot = false;
  # NOTE avoids setting kernelParams that are only relevant for kvm guests
  # Having this set to true will cause the system to hang on boot and
  # you will *not* be able to enter the luks password on the console
  hardware.kvmGuest = false;

  # Enable networking
  networking = {
    hostName = "lrz";
    firewall.enable = false;
  };
}
