{
  lib,
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix

    ../../profiles/workstation.nix

    ../../services/initrd-luks-ssh-unlock.nix
    ../../services/nixos-installer-boot-entry.nix
  ];

  home-manager.users.${config.mainUser.username} = {
    services.jellysync.enable = true;
    # Trial install of DankMaterialShell as a Waybar alternative (see
    # home-manager/gui/hyprland/quickshell-bar for the other one). Cycled
    # in via SUPER+SHIFT+B (toggle-bar.sh) alongside waybar/quickshell-bar;
    # not in Install.WantedBy so it doesn't autostart on its own.
    programs.dank-material-shell = {
      enable = true;
      systemd.enable = true;
      # Raw pkgs.glib collides with the gsettings wrapper from
      # modules/theme.nix; the VPN widget isn't needed for this trial.
      enableVPN = false;
    };
    systemd.user.services.dms.Install.WantedBy = lib.mkForce [ ];
  };

  hardware.cattle = false;
  initrd.wifi = {
    enable = true;
    interfaceName = "wlp195s0";
  };
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

  services.upower = {
    criticalPowerAction = "PowerOff";
    percentageCritical = 10;
    percentageAction = 5;
  };

  systemd.sleep.settings.Sleep = {
    MemorySleepMode = "deep";
  };

}
