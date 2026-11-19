{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.fullNix.androidBridge;

  api = pkgs.callPackage ../../../pkgs/nixpp/android-api.nix {
    inherit inputs;
    notificationTimeouts = config.programs.notify-send.android.timeout;
  };

  # The former native broker's commands, now Termux:API calls through the
  # app's am socket: one guest-to-Android channel instead of two.
  android-bridge = pkgs.writeShellApplication {
    name = "android-bridge";
    runtimeInputs = [
      api
      pkgs.coreutils
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/android-bridge.sh;
  };
in
{
  options.fullNix.androidBridge = {
    enable = lib.mkEnableOption ''
      the TermuxPP Android API commands (`termux-*`, `xdg-open`, `notify-send`)
      and `android-bridge`, which reach Android through the app's am socket'';
  };

  imports = [
    (lib.mkRemovedOptionModule [
      "fullNix"
      "androidBridge"
      "socket"
    ] "The native bridge broker is gone; android-bridge uses Termux:API through the app.")
  ];

  options.programs.notify-send.android.timeout = lib.mkOption {
    type = lib.types.submodule {
      options =
        lib.mapAttrs
          (
            urgency: default:
            lib.mkOption {
              type = lib.types.ints.between 0 2147483647;
              inherit default;
              description = "Default timeout for ${urgency} Android notifications, in milliseconds. Zero keeps the notification until dismissed.";
            }
          )
          {
            low = 4000;
            normal = 7000;
          };
    };
    default = { };
    description = "TermuxPP notify-send timeouts by urgency.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      android-bridge
      api
    ];
  };
}
