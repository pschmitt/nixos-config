{ config, pkgs, ... }:
{
  imports = [
    ../../modules/main-user.nix
    ../../modules/domains.nix

    ../../home-manager/base.nix
    ../../home-manager/gui/go-hass-agent
    ../../home-manager/work
    ../../home-manager/sops-standalone.nix
    ../../home-manager/devel/claude-remote.nix
    ../../home-manager/codex-ha-bridge.nix
    ../../services/nix-distributed-build.nix

    ./kvm-usb.nix
  ];

  domains.main = "brkn.lol";

  targets.genericLinux.enable = true;

  xdg.configFile."home-manager".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git";

  home = {
    inherit (config.mainUser) username homeDirectory;
    stateVersion = "26.05";
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
    "home-assistant/mqtt/username".sopsFile = ./secrets.sops.yaml;
    "home-assistant/mqtt/password".sopsFile = ./secrets.sops.yaml;
    "ssh/nix-remote-builder/privkey".mode = "0400";
  };
}
