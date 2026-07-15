{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.falcon-sensor.nixosModules.default ];

  options.custom.crowdstrike.customerIdFile = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Path to the CrowdStrike Falcon customer ID file.";
  };

  config =
    let
      customerIdFile =
        if config.custom.crowdstrike.customerIdFile != null then
          config.custom.crowdstrike.customerIdFile
        else
          config.sops.secrets."crowdstrike/customerId".path;
    in
    {
      # Overwrite the placeholder CID with the real one unless a caller provides
      # a runtime-only file, such as the dedicated Falcon VM.
      sops.secrets."crowdstrike/customerId" =
        lib.mkIf (config.custom.crowdstrike.customerIdFile == null)
          {
            sopsFile = ../../secrets/shared.sops.yaml;
          };

      services.falcon-sensor = {
        enable = true;
        cid = "00000000000000000000000000000000-00";
        kernelPackages = null;
      };

      # Separate service to initialize Falcon CID without hardening restrictions
      # This runs BEFORE falcon-sensor and has access to the CID file.
      systemd.services.falcon-sensor-init = {
        description = "Initialize CrowdStrike Falcon Sensor CID";
        wantedBy = [ ];
        before = [ "falcon-sensor.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeScript "falcon-init" ''
            #!${pkgs.bash}/bin/bash
            set -euo pipefail
            ln -sf ${pkgs.falcon-sensor-unwrapped}/opt/CrowdStrike/* /opt/CrowdStrike/
            ${pkgs.falcon-sensor}/bin/falconctl -s --trace=debug

            if [ -f ${customerIdFile} ]; then
              CID=$(cat ${customerIdFile})
              ${pkgs.falcon-sensor}/bin/falconctl -s --cid="$CID" -f
            else
              echo "CID secret not found at ${customerIdFile}!"
              exit 1
            fi

            ${pkgs.falcon-sensor}/bin/falconctl -g --cid
          '';
        };
      };

      systemd.services.falcon-sensor = {
        # Let's just not start this garbage service automatically
        wantedBy = lib.mkForce [ ];
        # Require the init service to run first
        requires = [ "falcon-sensor-init.service" ];
        after = [ "falcon-sensor-init.service" ];

        serviceConfig = {
          # upstream uses /var/run/falcond.pid - systemd complains about that:
          # PIDFile= references a path below legacy directory /var/run/, updating /var/run/falcond.pid → /run/falcond.pid; please update the unit file accordingly.
          PIDFile = lib.mkForce "/run/falcond.pid";

          # Remove ExecStartPre - CID setup now done by falcon-sensor-init service
          ExecStartPre = lib.mkForce [ ];

          # Systemd hardening - minimal restrictions for Falcon to work with bwrap
          # NOTE: ProtectHome, ProtectSystem disabled because bwrap needs mount permissions
          # Falcon uses bubblewrap for sandboxing which conflicts with strict filesystem isolation

          # Block access to sensitive directories using InaccessiblePaths
          InaccessiblePaths = [
            "/home" # User home directories
            "/root" # Root home directory
            "/run/secrets" # ALL secrets - Falcon CID is set by init service before hardening
            "/run/secrets.d" # Sops secret storage
            "/run/secrets-for-users.d" # User secrets
            "/run/user" # User runtime directories (includes Firefox, etc)
          ];

          # Kernel/system protections (these should work)
          ProtectKernelTunables = true; # Protect /proc/sys, /sys from writes
          ProtectKernelLogs = true; # Deny access to kernel logs
          ProtectHostname = true; # Prevent hostname changes
          ProtectClock = true; # Prevent system clock changes
          RestrictSUIDSGID = true; # Prevent SUID/SGID bit changes

          # Network restrictions
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
          ];

          # NOTE: ProtectSystem and ReadWritePaths removed - bwrap needs full filesystem access for mounts

          # Lock down personality to prevent exploitation
          LockPersonality = true;

          # Restrict realtime scheduling
          RestrictRealtime = true;

          # NOTE: RestrictNamespaces is NOT set because Falcon uses bubblewrap (bwrap)
          # which requires namespace creation for sandboxing during initialization

          # System call filtering - be more permissive for Falcon's needs
          # Falcon needs broader syscall access for security monitoring and sandboxing
          SystemCallFilter = [
            "@system-service"
            "@mount" # Required for bubblewrap (bwrap) sandboxing
            "bpf" # Allow eBPF syscall for kernel probing (prevents core dumps)
            "~@obsolete" # Block obsolete syscalls only
          ];
        };
      };

      nixpkgs.overlays = [
        (final: _prev: {
          falcon-sensor = final.falcon-sensor-wiit;
          falcon-sensor-unwrapped = final.falcon-sensor-wiit.unwrapped;
        })
      ];
    };
}
