{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../profiles/global/nix/overlays.nix
    ../../profiles/work/crowdstrike-falcon-sensor.nix
  ];

  networking.hostName = "falcon-sensor";
  system.stateVersion = "25.11";

  # The host provides this one-file, read-only mount immediately at boot.
  custom.crowdstrike.customerIdFile = "/run/falcon-secrets/customerId";
  # Falcon 7.29 does not support the host's 6.18 kernel; keep the guest on
  # the supported LTS line without changing ge2's kernel.
  services.falcon-sensor.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  networking.firewall.allowedTCPPorts = [ 22 ];
  users.users.root.openssh.authorizedKeys.keys = config.mainUser.authorizedKeys;

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

      # The VM is the security boundary. Falcon's sandboxing and kernel probes
      # need fewer systemd restrictions than the host-level deployment allowed.
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

  virtualisation.vmVariant = {
    virtualisation = {
      graphics = false;
      memorySize = 1024;
      cores = 1;
      diskSize = 8192;
      qemu.options = [ "-enable-kvm" ];
      forwardPorts = [
        {
          host.address = "127.0.0.1";
          host.port = 32526;
          guest.port = 22;
        }
      ];
      sharedDirectories.falcon-secrets = {
        source = "/run/falcon-sensor-vm-secrets";
        target = "/run/falcon-secrets";
        securityModel = "none";
      };
    };
  };
}
