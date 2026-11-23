{
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
  # Expose the AMD SMU so ryzenadj can adjust the HX 370 power limits.
  boot = {
    extraModulePackages = [
      config.boot.kernelPackages.ryzen-smu
    ];
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

  services.ppd-react.tdp = {
    enable = true;
    command = "${ryzenadjTdp}/bin/ryzenadj-tdp";
    profiles = {
      power-saver = {
        stapmLimit = 12000;
        fastLimit = 12000;
        slowLimit = 12000;
        apuSlowLimit = 12000;
      };
      balanced = {
        stapmLimit = 14000;
        fastLimit = 14000;
        slowLimit = 14000;
        apuSlowLimit = 14000;
      };
      performance = {
        stapmLimit = 24000;
        fastLimit = 28000;
        slowLimit = 28000;
        apuSlowLimit = 28000;
      };
    };
    batteryProfiles = {
      power-saver = {
        stapmLimit = 8000;
        fastLimit = 8000;
        slowLimit = 8000;
        apuSlowLimit = 8000;
      };
      balanced = {
        stapmLimit = 10000;
        fastLimit = 10000;
        slowLimit = 10000;
        apuSlowLimit = 10000;
      };
    };
  };
  services.ppd-react.batteryPowerSaverBrightnessPercent = 15;

  security.polkit.extraConfig = ''
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
}
