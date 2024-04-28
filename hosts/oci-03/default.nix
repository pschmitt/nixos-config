{ ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/oci.nix

    ../../misc/mmonit.nix
    ../../common/restic
  ];

  custom.useBIOS = false;

  # Enable networking
  networking = {
    hostName = "oci-03";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
