{
  config,
  lib,
  pkgs,
  ...
}:
let
  migrateScript = pkgs.writeScriptBin "migrate-fnuc-to-lrz" (
    builtins.readFile ../../scripts/migrate-fnuc-to-lrz.sh
  );
in
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../profiles/server

    # home-manager configuration (TEST!)
    ../../profiles/gui/linger.nix

    # FNUC-007: Native syslog-ng and logrotate service
    ../../services/syslog-server.nix

    # FNUC-008: Native fleet LUKS SSH unlock service
    ../../services/luks-ssh-unlock-fleet.nix

    # FNUC-009: Native SmokePing latency monitor
    ../../services/smokeping.nix

    # FNUC-010: Camera FTP upload and prune timer
    ../../services/reolink-ftp.nix

    # FNUC-012: WatchYourLAN host discovery service
    ../../services/watchyourlan.nix

    # FNUC-020: Emergency noVNC Web Console for Home Assistant VM
    ../../services/web-vnc-console.nix

    # FNUC-006: Native KVM USB passthrough watchdog
    ../../services/kvm-usb.nix
  ];

  services.kvm-usb-passthrough.enable = true;

  hardware.biosBoot = false;
  # NOTE avoids setting kernelParams that are only relevant for kvm guests
  # Having this set to true will cause the system to hang on boot and
  # you will *not* be able to enter the luks password on the console
  hardware.kvmGuest = false;

  # Auto-unlock encrypted data volume in initrd using key on root filesystem
  boot.initrd.luks.devices.data-encrypted = {
    keyFile = lib.mkForce "/sysroot/etc/crypttab.d/keyfiles/data";
  };

  # Enable networking
  networking = {
    hostName = "lrz";
    firewall.enable = false;

    wireless = {
      enable = true;
      interfaces = [ "wlp2s0" ];
      secretsFile = config.sops.templates."wpa_supplicant.secrets".path;
      networks."brkn-lan".pskRaw = "ext:wifi_home_psk";
    };
  };

  sops.secrets."wifi/home/psk" = { };

  sops.templates."wpa_supplicant.secrets" = {
    owner = "root";
    group = "wpa_supplicant";
    mode = "0440";
    content = ''
      wifi_home_psk=${config.sops.placeholder."wifi/home/psk"}
    '';
  };

  systemd = {
    network = {
      netdevs."10-hass-br0" = {
        netdevConfig = {
          Name = "hass-br0";
          Kind = "bridge";
          MACAddress = "6c:4b:90:e4:73:8c";
        };
        bridgeConfig = {
          STP = false;
          MulticastSnooping = true;
        };
      };

      networks = {
        "40-enp1s0f0" = {
          matchConfig.Name = "enp1s0f0";
          networkConfig.Bridge = "hass-br0";
          linkConfig.RequiredForOnline = "enslaved";
        };

        "40-hass-br0" = {
          matchConfig.Name = "hass-br0";
          networkConfig = {
            DHCP = "yes";
            IPv6PrivacyExtensions = "kernel";
          };
          dhcpV4Config.RouteMetric = 1024;
          ipv6AcceptRAConfig.RouteMetric = 1024;
        };
      };
    };

    services = {
      # FNUC-018: Scheduled warm pre-sync of fnuc data (HA VM, /mnt/sda1, /srv)
      # Runs completely non-disruptively while fnuc workloads remain live.
      fnuc-migration-presync = {
        description = "Warm pre-sync of fnuc data to lrz (non-disruptive)";
        path = with pkgs; [
          bash
          coreutils
          openssh
          rsync
          sudo
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

      # Never export the underlying root filesystem if the SATA mount is missing.
      nfs-server = {
        unitConfig.RequiresMountsFor = [ "/mnt/sda1" ];
        bindsTo = [ "mnt-sda1.mount" ];
        after = [ "mnt-sda1.mount" ];
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

  # FNUC-005: Headless virtualization for Home Assistant OS VM
  virtualisation.libvirtd = {
    enable = true;
    onShutdown = "shutdown";
    allowedBridges = [
      "virbr0"
      "hass-br0"
    ];
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    libvirt
    qemu_kvm
    migrateScript
    (writeShellScriptBin "define-ha-vm" ''
      exec ${pkgs.libvirt}/bin/virsh define ${./home-assistant.xml}
    '')
  ];

  services.nfs.server = {
    enable = true;
    exports = ''
      /mnt/sda1 10.5.0.0/22(rw,sync,no_subtree_check,no_root_squash,anonuid=1000,anongid=1000,mountpoint)
    '';
  };
}
