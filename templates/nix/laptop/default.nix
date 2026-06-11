{
  config,
  lib,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    # Interactive laptop base: global + GUI infra + Hyprland/GNOME under GDM +
    # laptop role features + work bundle + restic. Add extra desktops via
    # profiles/desktop-*.nix if needed.
    ../../profiles/workstation.nix

    ../../services/initrd-luks-ssh-unlock.nix
    ../../services/nixos-installer-boot-entry.nix
  ];

  hardware.cattle = false;

  networking = {
    hostName = lib.strings.trim (builtins.readFile ./HOSTNAME);
    firewall.enable = false;
  };

  home-manager.users.${config.mainUser.username}.services.go-hass-agent.enable = lib.mkForce false;
}
