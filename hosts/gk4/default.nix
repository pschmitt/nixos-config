{
  lib,
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/global
    ../../common/gui
    ../../common/laptop
    ../../services/restic
    ../../common/work

    ../../services/initrd-luks-ssh-unlock.nix
    ../../services/nixos-installer-boot-entry.nix
  ];

  home-manager.users.${config.mainUser.username}.services.jellysync.enable = true;

  hardware.cattle = false;
  console.keyMap = lib.mkForce "custom/gpdpocket4-de";

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
