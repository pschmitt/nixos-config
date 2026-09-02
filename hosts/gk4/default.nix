{
  lib,
  config,
  pkgs,
  inputs,
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
      # Read-only Syncthing widget (syncthing.service already runs system-wide
      # here via profiles/laptop/syncthing.nix).
      plugins.syncshell.src = "${
        inputs.syncshell-dms.packages.${pkgs.system}.default
      }/share/dms-plugins/syncshell";
      # Declarative snapshot of ~/.config/DankMaterialShell/settings.json
      # (bar layout, theme, fonts) and plugin_settings.json (enabled
      # plugins). NOTE: this makes both files Nix-managed symlinks, so the
      # DMS settings UI / `dms ipc` can no longer save changes to them —
      # further tweaks have to go through this file + a redeploy.
      managePluginSettings = true;
      settings = builtins.fromJSON (builtins.readFile ./dank-material-shell-settings.json);
    };
    systemd.user.services.dms.Install.WantedBy = lib.mkForce [ ];
    # These existed as plain runtime files from earlier live DMS/plugin
    # edits; force lets home-manager take over managing them now.
    xdg.configFile."DankMaterialShell/settings.json".force = true;
    xdg.configFile."DankMaterialShell/plugin_settings.json".force = true;
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
