{ ... }: {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../server
    ../../server/oci.nix

    ../../common/mail
  ];

  custom.useBIOS = false;

  # Enable networking
  networking = {
    hostName = "oci-04";
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };
}
