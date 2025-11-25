{ lib, ... }:
{
  imports = [
    ./hardware-configuration.nix

    ../../common/global
    ../../common/gui
    ../../common/laptop
    ../../common/restic
    ../../common/work

    ../../misc/initrd-luks-ssh-unlock.nix
    ../../services/nixos-installer-boot-entry.nix
  ];

  custom.cattle = false;

  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    firewall.enable = false;
  };

  systemd.services.go-hass-agent.enable = lib.mkForce false;
}
