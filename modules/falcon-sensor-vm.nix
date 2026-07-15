{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.falcon-sensor-vm;
in
{
  options.services.falcon-sensor-vm = {
    enable = lib.mkEnableOption "CrowdStrike Falcon Sensor virtual machine";

    package = lib.mkOption {
      type = lib.types.package;
      description = "NixOS VM runner package built by config.system.build.vm.";
    };

    customerIdFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to the CrowdStrike customer ID file staged for the guest.";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "falcon-sensor-vm";
      description = "StateDirectory name used for the VM disk and runtime files.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.falcon-sensor-vm = {
      description = "CrowdStrike Falcon Sensor VM";
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "sops-nix.service"
      ];
      serviceConfig = {
        Type = "simple";
        StateDirectory = cfg.stateDirectory;
        RuntimeDirectory = "${cfg.stateDirectory}-secrets";
        Restart = "always";
        RestartSec = "10s";
        ExecStartPre = "+${pkgs.coreutils}/bin/install -m 0400 ${cfg.customerIdFile} /run/${cfg.stateDirectory}-secrets/customerId";
        ExecStart = "${cfg.package}/bin/run-falcon-sensor-vm";
        WorkingDirectory = "/var/lib/${cfg.stateDirectory}";
      };
    };
  };
}
