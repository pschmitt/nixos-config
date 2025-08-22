{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/global

    ../../common/mail

    # XXX Below imports initrd-luks-ssh-unlock etc
    # ../../server
    # So we only import what we really need here:
    ../../server/dotfiles.nix
    # ../../monit.nix
    # ../../netbird.nix
    # ../../restic.nix
  ];

  custom.raspberryPi = true;
  custom.cattle = true;
  custom.kvmGuest = false;

  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);

    # Disable the firewall altogether.
    firewall = {
      enable = false;
      # allowedTCPPorts = [ ... ];
      # allowedUDPPorts = [ ... ];
    };

    wireless = {
      enable = true;
      userControlled.enable = true;
      # iwd.enable = true;
      networks = {
        "brkn-lan" = {
          psk = "changeme";
        };
      };
    };
  };

  # environment.systemPackages = with pkgs; [ ];
}
