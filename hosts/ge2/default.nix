{ inputs, lib, ... }:
{
  imports = [
    inputs.hardware.nixosModules.common-cpu-intel
    inputs.hardware.nixosModules.common-pc-ssd

    ./hardware-configuration.nix
    ./nvidia.nix
    # ./luks-remote.nix

    ../../common/global
    ../../common/gui
    ../../common/laptop
    ../../common/restic
    ../../common/snek
    ../../common/sshfs
    ../../common/work

    ../../misc/nfs-client.nix
  ];

  # FIXME MIPI Camera
  # hardware.ipu6 = {
  #   enable = true;
  #   # NOTE ipu6ep is for Raptor Lake
  #   platform = "ipu6ep";
  # };

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  services.logind.lidSwitchExternalPower = lib.mkForce "ignore";

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
  };
}
