{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../server
    ../../server/optimist.nix
  ];

  custom.cattle = true;

  # Increase verbosity only on this host to debug
  # initrd networking/SSH bring-up and early boot.
  boot = {
    initrd.verbose = true;
    # Kernel verbosity on consoles
    consoleLogLevel = 7;
    # Add verbose logging for initrd/systemd and udev
    kernelParams = [
      "loglevel=7"
      "rd.systemd.log_target=console"
      # Also increase regular systemd logging to console for completeness
      "systemd.log_target=console"
    ];
  };

  # Enable networking
  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  # environment.systemPackages = with pkgs; [ ];
}
