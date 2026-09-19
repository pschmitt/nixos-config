{ lib, pkgs, ... }:
let
  migrateScript = pkgs.writeScriptBin "migrate-fnuc-to-lrz" (
    lib.concatMapStringsSep "\n" builtins.readFile [
      ../../scripts/migrate-fnuc-to-lrz/lib.sh
      ../../scripts/migrate-fnuc-to-lrz/sda1.sh
      ../../scripts/migrate-fnuc-to-lrz/srv.sh
      ../../scripts/migrate-fnuc-to-lrz/ha-vm.sh
      ../../scripts/migrate-fnuc-to-lrz/main.sh
    ]
  );

  # One presync service/timer per migrate-fnuc-to-lrz target, so a slow or
  # stuck target (e.g. the HA VM snapshot dance) can't hold up the others,
  # and each shows up as its own unit in systemctl/journalctl.
  presyncTargets = {
    sda1 = {
      description = "/mnt/sda1 (frigate, reolink)";
      calendar = "07:00";
    };
    srv = {
      description = "/srv (syslog-ng, smokeping, netalertx, etc.)";
      calendar = "07:20";
    };
    ha-vm = {
      description = "the Home Assistant OS VM";
      calendar = "07:40";
    };
  };

  presyncUnitName = target: "fnuc-migration-presync-${target}";
in
{
  environment.systemPackages = [ migrateScript ];

  systemd = {
    tmpfiles.rules = [ "d /var/lib/fnuc-migration 0750 pschmitt users -" ];

    # FNUC-018: Scheduled warm pre-sync of fnuc data to lrz, split per target.
    # Runs completely non-disruptively while fnuc workloads remain live.
    services =
      lib.mapAttrs' (
        target: cfg:
        lib.nameValuePair (presyncUnitName target) {
          description = "Warm pre-sync of ${cfg.description} to lrz (non-disruptive)";
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
            ExecStart = "${migrateScript}/bin/migrate-fnuc-to-lrz --presync ${target}";
          };
        }
      ) presyncTargets
      // {
        # FNUC-005: Enforce that the Home Assistant VM on lrz remains strictly POWERED OFF
        # and autostart disabled until the final cutoff day.
        home-assistant-vm-guard = {
          description = "Enforce powered-off state for Home Assistant VM on lrz before cutover";
          wantedBy = [ "multi-user.target" ];
          after = [
            "libvirtd.service"
            "home-assistant-vm-init.service"
          ];
          requires = [
            "libvirtd.service"
            "home-assistant-vm-init.service"
          ];
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

    timers = lib.mapAttrs' (
      target: cfg:
      lib.nameValuePair (presyncUnitName target) {
        description = "Daily warm pre-sync of ${cfg.description} to lrz (${cfg.calendar})";
        timerConfig = {
          OnCalendar = cfg.calendar;
          Persistent = true;
          RandomizedDelaySec = "10m";
        };
        wantedBy = [ "timers.target" ];
      }
    ) presyncTargets;
  };
}
