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

  services.ppd-react.tdp = {
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
