# workstation — interactive desktop/laptop hosts (ge2, gk4, x13): the shared
# GUI + laptop + work base every personal machine runs.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hyprRdp = inputs.hypr-rdp.packages.${pkgs.stdenv.hostPlatform.system}.hypr-rdp.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (inputs.nixos-config-private.outPath + "/pkgs/hypr-rdp-rotated-output.patch")
    ];
  });
in
{
  imports = [
    ../../base
    ../../features/network
    ../../features/network/fnuc-nix-cache.nix
    ../../features/desktop
    ../../features/diagnostics/reboot-logging.nix

    # Desktop + display manager; these laptops run Hyprland and GNOME under
    # GDM.
    ../../features/desktop/hyprland.nix
    ../../features/desktop/gnome.nix
    ../../features/desktop/gdm.nix

    ../laptop

    # Extra features currently run by all three laptops.
    ../../features/network/snek
    ../laptop/tor.nix
    ../laptop/wireshark.nix
    ../laptop/nrf.nix
    ../laptop/waydroid.nix
    ../../features/work/vpn/openvpn.nix

    ../../../services/restic
    ../../../services/autoupgrade.nix
  ];

  system.nixosConfigSymlink.enable = true;
  programs.hrworks.enable = true;

  # Install the nixos-upgrade service on laptops, but don't schedule it —
  # unlike servers, laptops upgrade on demand (systemctl start
  # nixos-upgrade.service), not on a timer.
  systemd.timers.nixos-upgrade.enable = false;

  home-manager.users.${config.mainUser.username} = {
    imports = [
      ../../../home-manager/ssh-clipboard-peers.nix
    ];
    home.packages = [ hyprRdp ];
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
