{ pkgs, ... }:
let
  migrateScript = pkgs.writeScriptBin "migrate-fnuc-to-lrz" (
    builtins.readFile ../../scripts/migrate-fnuc-to-lrz.sh
  );
in
{
  environment.systemPackages = [ migrateScript ];

  systemd = {
    tmpfiles.rules = [ "d /var/lib/fnuc-migration 0750 pschmitt users -" ];

    services = {
      # FNUC-018: Scheduled warm pre-sync of fnuc data (HA VM, /mnt/sda1, /srv)
      # Runs completely non-disruptively while fnuc workloads remain live.
      fnuc-migration-presync = {
        description = "Warm pre-sync of fnuc data to lrz (non-disruptive)";
        unitConfig.ConditionPathExists = "!/var/lib/fnuc-migration/cutover";
        path = with pkgs; [
          bash
          coreutils
          openssh
          rsync
          sudo
          util-linux
          gawk
        ];
        environment = {
          HOME = "/home/pschmitt";
        };
        serviceConfig = {
          Type = "oneshot";
          User = "pschmitt";
          Group = "users";
          ExecStart = "${migrateScript}/bin/migrate-fnuc-to-lrz --presync all";
        };
      };

      # FNUC-005: Enforce that the Home Assistant VM on lrz remains strictly POWERED OFF
      # and autostart disabled until the final cutoff day.
      home-assistant-vm-guard = {
        description = "Enforce powered-off state for Home Assistant VM on lrz before cutover";
        wantedBy = [ "multi-user.target" ];
        after = [ "libvirtd.service" ];
        requires = [ "libvirtd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "guard-ha-vm-offline" ''
            if ${pkgs.libvirt}/bin/virsh dominfo home-assistant >/dev/null 2>&1; then
              state=$(${pkgs.libvirt}/bin/virsh domstate home-assistant 2>/dev/null || echo "shut off")
              if [[ "$state" =~ "running" ]]; then
                echo "CRITICAL: home-assistant VM is running on lrz before cutoff! Shutting it down immediately..." >&2
                ${pkgs.libvirt}/bin/virsh destroy home-assistant || true
              fi
              # Ensure autostart is disabled
              ${pkgs.libvirt}/bin/virsh autostart --disable home-assistant 2>/dev/null || true
            fi
          '';
        };
      };
    };

    timers.fnuc-migration-presync = {
      description = "Daily warm pre-sync of fnuc data to lrz (07:00)";
      timerConfig = {
        OnCalendar = "07:00";
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
