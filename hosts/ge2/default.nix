{ pkgs, inputs, ... }: {
  imports = [
    inputs.hardware.nixosModules.common-cpu-intel
    inputs.hardware.nixosModules.common-pc-ssd
    inputs.hardware.nixosModules.common-pc-laptop-acpi_call

    ./hardware-configuration.nix
    ./nvidia.nix
    # ./luks-remote.nix

    ../../common/global
    ../../common/gui
    ../../common/sshfs
    ../../common/work
  ];


  # FIXME MIPI Camera
  # hardware.ipu6 = {
  #   enable = true;
  #   platform = "ipu6ep";
  # };

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking = {
    hostName = "ge2"; # Define your hostname.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };

    # # FIXME DIRTYFIX for task sync
    # # We have a weird resolution bug:
    # # $ ping -c 2 oAci-02.heimat.dev
    # # 👆 fails to resolve
    # extraHosts =
    #   ''
    #   45.94.108.232 test.keycloak-dev.sre.gec.io
    #   '';
  };
}
