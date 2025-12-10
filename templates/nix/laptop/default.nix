{ lib, ... }:
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

  hardware.cattle = false;

  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    firewall.enable = false;
  };

  systemd.services.go-hass-agent.enable = lib.mkForce false;
}
