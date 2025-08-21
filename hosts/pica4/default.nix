{ lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix


    ../../common/global

    ../../common/mail

    # Below imports initrd-luks-ssh-unlock etc
    # ../../server
    ../../server/dotfiles.nix
    # ../../monit.nix
    # ../../netbird.nix
    # ../../restic.nix
  ];

  custom.cattle = true;

  # Here for force-set a few settings that are set by bootloader.nix, which
  # overrides the nixos-hardware settings.
  boot = {
    kernelPackages = lib.mkForce pkgs.linuxKernel.packages.linux_rpi4;
    loader = {
      grub.enable = lib.mkForce false;
      systemd-boot.enable = lib.mkForce false;
    };
  };

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
