{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../profiles/base/nix/overlays.nix
    ../../profiles/base/users/hermes.nix
    ../../profiles/features/work/crowdstrike-falcon-sensor.nix
  ];

  networking.hostName = "falcon-sensor";
  system.stateVersion = "25.11";

  services.falcon-sensor.customerIdFile = "/run/falcon-secrets/customerId";
  services.falcon-sensor.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;

  systemd.services = {
    falcon-sensor-init = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStartPre = [
        "+${pkgs.coreutils}/bin/mkdir -p /lib"
        "+${pkgs.coreutils}/bin/ln -sfn /run/booted-system/kernel-modules/lib/modules /lib/modules"
      ];
    };
    falcon-sensor = {
      wantedBy = lib.mkForce [ "multi-user.target" ];
      before = lib.mkForce [ ];
      unitConfig.DefaultDependencies = lib.mkForce true;
      serviceConfig = {
        InaccessiblePaths = lib.mkForce [ ];
        ProtectKernelTunables = lib.mkForce false;
        ProtectKernelLogs = lib.mkForce false;
        ProtectHostname = lib.mkForce false;
        ProtectClock = lib.mkForce false;
        RestrictSUIDSGID = lib.mkForce false;
        RestrictAddressFamilies = lib.mkForce [ ];
        LockPersonality = lib.mkForce false;
        RestrictRealtime = lib.mkForce false;
        SystemCallFilter = lib.mkForce [ ];
      };
    };
  };
}
