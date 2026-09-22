{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    # Shared home config tree (osConfig-free); host facts set via host.* below.
    ../../home-manager/home.nix

    ../../home-manager/gui/go-hass-agent
    ../../modules/home-manager/claude-remote-control.nix
    ../../modules/home-manager/codex-remote-control.nix
    inputs.codex-ha-bridge.homeManagerModules.default
    ../../home-manager/ssh-clipboard-peers.nix
    ../../services/nix-distributed-build.nix

    ./claude-work-warmup.nix
    ./agy-warmup.nix
    ../../profiles/server/interactive/syncthing-home.nix
  ];

  services.ssh-clipboard = {
    headlessX11 = true;
    sessionDisplay = ":99";
  };

  # Matches every other host (profiles/global/nix/overlays.nix), which fnuc
  # doesn't import as a standalone home-manager host.
  nixpkgs.config.allowUnfree = true;

  # nixos-install enters the target system while installing the boot loader
  # and needs util-linux's mount command there.
  environment.systemPackages = [ pkgs.util-linux ];

  systemd.tmpfiles.rules = [ "d /var/lib/fnuc-migration 0750 pschmitt users -" ];

  domains.main = "brkn.lol";

  targets.genericLinux.enable = true;

  xdg.configFile."home-manager".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git";

  home = {
    inherit (config.mainUser) username homeDirectory;
    packages = [
      pkgs.syncthingtui
      pkgs.stui
    ];
  };

  host = {
    # fnuc's host-specific secrets (MQTT creds wired by the go-hass-agent module)
    sopsFile = inputs.nixos-config-private.outPath + "/hosts/fnuc/secrets.sops.yaml";
    stateVersion = "26.05";
    manageAuthorizedKeys = true;
  };

  # Allow Home Assistant's KVM USB watchdog and Hermes on rofl-10 to use
  # scoped main-user SSH access rather than a shared/global account. fnuc has
  # no NixOS user module (standalone Home Manager host), so Hermes can't get
  # its own dedicated Unix account here the way it does on rofl-13/rofl-14
  # (see profiles/global/users/hermes.nix); it still logs in as
  # mainUser, but with its own key rather than sharing nix-remote-builder's.
  mainUser.extraAuthorizedKeys = lib.mkAfter [
    # Home Assistant container on hv, used by the KVM USB replug automation.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKtJvOe/V+obZ1lS2L/qUAUVDUSFapVKin07BUZSHAU7 root@a0d7b954-ssh"
    config.custom.hermes.sshPublicKey
  ];

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
    package = pkgs.nix;
    settings.max-jobs = 0;

    gc = {
      automatic = true;
      dates = "03:00:00";
      options = "--delete-older-than 5d";
      randomizedDelaySec = "30m";
    };
  };

  services = {
    codex-ha-bridge = {
      enable = true;
      environmentFile = config.sops.secrets."codex-ha-bridge/env".path;
    };

    # lnxlink = {
    #   enable = true;
    #   clientId = "fnuc";
    #   mqttUsernameSecret = "home-assistant/mqtt/username";
    #   mqttPasswordSecret = "home-assistant/mqtt/password";
    #   exclude = [
    #     "audio_select"
    #     "beacondb"
    #     "boot_select"
    #     "brightness"
    #     "camera_used"
    #     "clipboard"
    #     "display_env"
    #     "fullscreen"
    #     "gamepad"
    #     "gpio"
    #     "gpu"
    #     "idle"
    #     "inference_time"
    #     "ir_remote"
    #     "keyboard_hotkeys"
    #     "media"
    #     "microphone_used"
    #     "mouse"
    #     "power_profile"
    #     "restful"
    #     "screen_onoff"
    #     "screenshot"
    #     "send_keys"
    #     "speaker_used"
    #     "speech_recognition"
    #     "steam"
    #     "webcam"
    #   ];
    #   scriptPackages = with pkgs; [
    #     gnupg
    #     rbw
    #   ];
    #   bashExpose = [
    #     {
    #       name = "RBW";
    #       command = "${config.xdg.configHome}/lnxlink/scripts/rbw.sh";
    #       type = "binary_sensor";
    #       icon = "mdi:vault";
    #       update_interval = 30;
    #     }
    #     {
    #       name = "GPG Main Key";
    #       command = "${config.xdg.configHome}/lnxlink/scripts/gpg-main-key.sh";
    #       type = "binary_sensor";
    #       icon = "mdi:key-variant";
    #       update_interval = 60;
    #     }
    #   ];
    # };

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

  sops.secrets = {
    "codex-ha-bridge/env".mode = "0600";
    "ssh/nix-remote-builder/privkey".mode = "0400";
  };
}
