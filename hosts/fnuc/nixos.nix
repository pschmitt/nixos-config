{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../profiles/roles/interactive-server.nix
    ../../profiles/gui/linger.nix
    ../../profiles/network/ha-sshfs.nix

    ../../services/syslog-server.nix
    ../../services/luks-ssh-unlock-fleet.nix
    ../../services/smokeping.nix
    ../../services/reolink-ftp.nix
    ../../services/watchyourlan.nix
    ../../services/web-vnc-console.nix
    ../../services/kvm-usb.nix
    ../../services/browser-mcp-chromium-container.nix
    ../../services/nix-distributed-build.nix

    ./backups.nix
    ./monit.nix
    ./nfs.nix
    ./networking.nix
    ./hass-vm.nix

    ../../profiles/roles/homelab-server.nix
  ];

  services = {
    fwupd.enable = true;
    kvm-usb-passthrough.enable = true;
    watchyourlan.interfaces = [
      "hass-br0"
      "wlp0s20f3"
    ];
  };

  hardware = {
    biosBoot = false;
    kvmGuest = false;
  };

  systemd.services.nix-daemon.serviceConfig = {
    CPUWeight = 10;
    CPUQuota = "200%";
    IOWeight = 10;
    MemoryHigh = "4G";
    MemoryMax = "6G";
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "40%";
    TasksMax = 4096;
  };

  # Auto-unlock the encrypted data disk using the key installed on the root
  # filesystem by the initrd SSH-unlock preparation.
  boot.initrd.luks.devices.data-encrypted = {
    keyFile = lib.mkForce "/sysroot/etc/crypttab.d/keyfiles/data";
  };

  mainUser.extraAuthorizedKeys = lib.mkAfter [
    # Home Assistant container on hv, used by the KVM USB replug automation.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtJvOe/V+obZ1lS2L/qUAUVDUSFapVKin07BUZSHAU7 root@a0d7b954-ssh"
    config.custom.hermes.sshPublicKey
  ];

  home-manager.users.${config.mainUser.username} =
    { config, pkgs, ... }:
    {
      imports = [
        ../../home-manager/gui/go-hass-agent
        ../../modules/home-manager/claude-remote-control.nix
        ../../modules/home-manager/codex-remote-control.nix
        inputs.codex-ha-bridge.homeManagerModules.default
        ../../home-manager/ssh-clipboard-peers.nix
        ../../services/nix-distributed-build.nix

        ./claude-work-warmup.nix
        ./agy-warmup.nix
        ./wl-paste-shim.nix
      ];

      services = {
        ssh-clipboard = {
          headlessX11 = true;
          sessionDisplay = ":99";
        };

        codex-ha-bridge = {
          enable = true;
          environmentFile = config.sops.secrets."codex-ha-bridge/env".path;
        };

        go-hass-agent = {
          enable = true;
          enableDesktopScripts = false;
          mqttUsernameSecret = "home-assistant/mqtt/username";
          mqttPasswordSecret = "home-assistant/mqtt/password";
          scriptPackages = with pkgs; [
            jq
            rbw
          ];
        };
      };

      xdg.configFile."home-manager".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git";

      systemd.user = {
        services.kubeconfig-update = {
          Unit.Description = "Update kubeconfigs";
          Service = {
            Type = "oneshot";
            ExecStartPre = "${config.home.homeDirectory}/bin/zhj rancher::login-cli-all";
            ExecStart = "${config.home.homeDirectory}/bin/zhj kubectl::kubeconfig-export-rancher";
          };
        };

        timers.kubeconfig-update = {
          Unit.Description = "Periodically update kubeconfigs";
          Timer = {
            OnCalendar = "12:30:00";
            RandomizedDelaySec = "30m";
            Persistent = true;
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };

      nix = {
        settings.max-jobs = 0;
      };

      sops.secrets = {
        "codex-ha-bridge/env".mode = "0600";
        "ssh/nix-remote-builder/privkey".mode = "0400";
      };
    };
}
