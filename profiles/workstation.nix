# workstation — interactive desktop/laptop hosts (ge2, gk4, x13): the shared
# GUI + laptop + work base every personal machine runs.
{ config, lib, ... }:
{
  imports = [
    ./global
    ./gui

    # Desktop + display manager (opt-in roles); these laptops run Hyprland and
    # GNOME under GDM.
    ./desktop-hyprland.nix
    ./desktop-gnome.nix
    ./display-manager-gdm.nix

    ./laptop

    # Role features (opt-in) currently run by all three laptops.
    ./vpn-mullvad.nix
    ./privacy-tor.nix
    ./net-debug.nix
    ./nrf-dev.nix
    ./android-waydroid.nix
    ./work-wiit.nix

    ../services/restic
  ];

  home-manager.users.${config.mainUser.username} = {
    imports = [ ../home-manager/nixos-pull.nix ];
    services.go-hass-agent.enableWorkstationCommands = true;
  };

  # Keep local builds from taking down interactive desktop sessions.
  zramSwap = {
    enable = lib.mkDefault true;
    memoryPercent = lib.mkDefault 50;
    priority = lib.mkDefault 100;
  };

  nix.settings = {
    max-jobs = lib.mkDefault 4;
    cores = lib.mkDefault 4;
  };

  systemd.services.nix-daemon.serviceConfig = {
    CPUWeight = lib.mkDefault 50;
    IOWeight = lib.mkDefault 50;
    MemoryHigh = lib.mkDefault "14G";
    MemoryMax = lib.mkDefault "16G";
    ManagedOOMMemoryPressure = lib.mkDefault "kill";
    ManagedOOMMemoryPressureLimit = lib.mkDefault "60%";
  };
}
