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
    # Battery Icon plugin (profiles/laptop/noctalia.nix) defaults to BAT0;
    # gk4's kernel exposes its battery as BATT instead. Its 80% charge cap
    # lives purely in the GPD BIOS -- no charge_control_* in sysfs, no vendor
    # module, nothing from upower -- so the plugin infers it from behaviour
    # instead (full_at = 0). Pin full_at = 80 here if that ever misreads.
    programs.noctalia.settings.plugin_settings."pschmitt/battery-icon".battery_device = "BATT";
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
