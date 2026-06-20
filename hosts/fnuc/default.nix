{ config, pkgs, ... }:
{
  imports = [
    # Shared home config tree (osConfig-free); host facts set via host.* below.
    ../../home-manager/home.nix

    ../../home-manager/gui/go-hass-agent
    ../../home-manager/devel/claude-remote.nix
    ../../modules/home-manager/codex-remote-control.nix
    ../../home-manager/codex-ha-bridge.nix
    ../../services/nix-distributed-build.nix

    ./kvm-usb.nix
    ./nix-daemon.nix
  ];

  xmr.mining.enableSync = true;

  domains.main = "brkn.lol";

  targets.genericLinux.enable = true;

  xdg.configFile."home-manager".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git";

  home = {
    inherit (config.mainUser) username homeDirectory;
  };

  host = {
    # fnuc's host-specific secrets (MQTT creds wired by the go-hass-agent module)
    sopsFile = ./secrets.sops.yaml;
    stateVersion = "26.05";
  };

  systemd.user.services.kubeconfig-update = {
    Unit.Description = "Update kubeconfigs";
    Service = {
      Type = "oneshot";
      ExecStartPre = "${config.home.homeDirectory}/bin/zhj rancher::login-cli-all";
      ExecStart = "${config.home.homeDirectory}/bin/zhj kubectl::kubeconfig-export-rancher";
    };
  };

  systemd.user.timers.kubeconfig-update = {
    Unit.Description = "Periodically update kubeconfigs";
    Timer = {
      OnCalendar = "12:30:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  services = {
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

    home-manager.autoUpgrade = {
      enable = true;
      frequency = "02:30";
      useFlake = true;
      flakeDir = "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git";
      flags = [
        "-b"
        "hm-backup"
      ];
      preSwitchCommands = [
        "${pkgs.gitMinimal}/bin/git pull"
      ];
    };
  };

  nix.package = pkgs.nix;
  nix.settings.max-jobs = 0;

  sops.secrets = {
    "ssh/nix-remote-builder/privkey".mode = "0400";
  };
}
