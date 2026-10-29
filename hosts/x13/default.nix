{ config, ... }:
{
  imports = [
    ../../profiles/specializations/workstation
    ../../services/nixos-installer-boot-entry.nix

    ./fprintd.nix
    ./hardware-configuration.nix
    ./networking.nix
    ./prompt.nix
    ./zsh.nix
  ];

  home-manager.users.${config.mainUser.username}.services.gnome-keyring.autoUnlockSops = true;

  # Pinned per host: bumping it changes stateful service defaults.
  # https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion
  system.stateVersion = "25.11";
}
