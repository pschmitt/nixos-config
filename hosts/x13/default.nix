{
  inputs,
  ...
}:
{
  imports = [
    inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-gpu-amd
    inputs.hardware.nixosModules.common-pc-ssd

    ./hardware-configuration.nix

    ../../common/global
    ../../common/gui
    ../../common/laptop
    ../../common/restic
    ../../common/snek
    ../../common/sshfs
    ../../common/work
    ../../services/nfs/nfs-client-all.nix
  ];

  custom.cattle = false;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking = {
    hostName = "x13"; # Define your hostname.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  # boot.kernelPackages = lib.mkForce pkgs.linuxPackages_zen;

  services.fprintd.enable = true;
}
