{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./iio-hyprland.nix
    ../../misc/fprintd.nix
    ../../misc/touchscreen.nix

    ../../common/global
    ../../common/gui
    ../../common/laptop
    ../../common/restic
    ../../common/snek
    ../../common/sshfs
    ../../common/work
    ../../services/nfs/nfs-client-all.nix

    ../../services/nixos-installer-boot-entry.nix
  ];

  custom.cattle = false;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking = {
    hostName = "gk4";
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };
  };

  systemd.services.go-hass-agent.enable = lib.mkForce false;
}
