{
  lib,
  config,
  pkgs,
  ...
}:
let
  gpdFanCurve = pkgs.writeShellApplication {
    name = "gpd-fan-curve";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./scripts/gpd-fan-curve.sh;
  };
  ryzenadjTdp = pkgs.writeShellApplication {
    name = "ryzenadj-tdp";
    runtimeInputs = [ pkgs.ryzenadj ];
    text = builtins.readFile ./scripts/ryzenadj-tdp.sh;
  };
  gpdPowerctl = pkgs.writeShellApplication {
    name = "gpd-powerctl";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.power-profiles-daemon
      pkgs.systemd
      ryzenadjTdp
    ];
    text = builtins.readFile ./scripts/gpd-powerctl.sh;
  };
in
{
  imports = [
    ./hardware-configuration.nix

    ../../profiles/roles/workstation.nix

    ../../services/initrd-luks-ssh-unlock.nix
    ../../services/nixos-installer-boot-entry.nix
  ];

  home-manager.users.${config.mainUser.username} = {
    services.jellysync.enable = true;
    # Battery Icon plugin (profiles/laptop/noctalia.nix) defaults to BAT0;
    # gk4's kernel exposes its battery as BATT instead. Its 80% charge cap
    # lives purely in the GPD BIOS -- no charge_control_* in sysfs, no vendor
    # module, nothing from upower. Set the known cap explicitly so the icon
    # treats 80% as visually full while keeping the real percentage as its label.
    programs.noctalia.settings.plugin_settings."pschmitt/battery-icon" = {
      battery_device = "BATT";
      charge_limit_as_full = true;
      full_at = 80;
      scale_percentage_to_charge_limit = false;
      show_fan_controls = false;
      show_tdp_controls = true;
    };
    programs.noctalia.settings.plugin_settings."pschmitt/fan-control".thermal_zone = "thermal_zone1";

    # ge2 sits to the left of gk4.
    services.lan-mouse = {
      enable = true;
      autoStart = false;
      peers = [
        {
          name = "ge2";
          position = "left";
        }
      ];
    };
  };

  hardware.cattle = false;

  # Expose the AMD SMU so ryzenadj can adjust the HX 370 power limits.
  boot = {
    extraModulePackages = [ config.boot.kernelPackages.ryzen-smu ];
    kernelModules = [ "ryzen_smu" ];
  };

  environment.systemPackages = [
    gpdFanCurve
    gpdPowerctl
    pkgs.ryzenadj
    ryzenadjTdp
  ];

  systemd.services.gpd-fan-curve = {
    description = "Temperature-dependent GPD Pocket 4 fan control";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      ExecStart = "${gpdFanCurve}/bin/gpd-fan-curve";
      ExecStopPost = "${gpdFanCurve}/bin/gpd-fan-curve --safe";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Re-enter manual curve control after firmware/kernel resume handling.
  powerManagement.resumeCommands = "systemctl restart gpd-fan-curve.service";

  services = {
    kmscon = {
      config = {
        rotate = "right";
        "xkb-keymap" = "${pkgs.custom-keymaps}/share/keymaps/custom/gpdpocket4-de.xkb";
      };
    };

    ppd-react.tdp = {
      enable = true;
      command = "${ryzenadjTdp}/bin/ryzenadj-tdp";
      profiles = {
        power-saver = {
          stapmLimit = 15000;
          fastLimit = 15000;
          slowLimit = 15000;
          apuSlowLimit = 15000;
        };
        balanced = {
          stapmLimit = 20000;
          fastLimit = 20000;
          slowLimit = 20000;
          apuSlowLimit = 20000;
        };
        performance = {
          stapmLimit = 24000;
          fastLimit = 28000;
          slowLimit = 28000;
          apuSlowLimit = 28000;
        };
      };
    };

    upower = {
      criticalPowerAction = "PowerOff";
      percentageCritical = 10;
      percentageAction = 5;
    };
  };

  security.polkit = {
    extraConfig = ''
      polkit.addRule(function (action, subject) {
        if (action.id == "org.freedesktop.policykit.exec") {
          if (
            (
              action.lookup("program") == "/run/current-system/sw/bin/ryzenadj-tdp" ||
              action.lookup("program") == "${ryzenadjTdp}/bin/ryzenadj-tdp"
            ) &&
            subject.user == "${config.mainUser.username}"
          ) {
            return polkit.Result.YES;
          }
        }
      });
    '';
  };

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

  systemd.sleep.settings.Sleep = {
    MemorySleepMode = "deep";
  };

}
