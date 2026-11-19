{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.fullNix.androidBridge;

  android-bridge = pkgs.runCommand "android-bridge" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
    install -Dm755 ${./scripts/android-bridge-client.py} $out/libexec/android-bridge-client.py
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/android-bridge \
      --add-flags "-I $out/libexec/android-bridge-client.py" \
      --set-default ANDROID_BRIDGE_SOCKET ${lib.escapeShellArg cfg.socket}
  '';
in
{
  options.fullNix.androidBridge = {
    enable = lib.mkEnableOption ''
      the `android-bridge` command: a guest client for the separately started
      native broker (`android-bridge.py serve`). The guest cannot execute
      Bionic helpers, so it asks the broker for an allowlisted `battery-status`
      or `toast`. Without a running broker the command fails with start
      instructions. This module does not start or persist the broker'';

    socket = lib.mkOption {
      type = lib.types.strMatching "/tmp/[A-Za-z0-9._/-]+";
      default = "/tmp/android-bridge/bridge.sock";
      description = ''
        Guest path of the broker socket; the broker's `--socket-dir` and
        `--socket-name` must map to it (guest `/tmp` is the runtime's `root/tmp`).
        Keep it short: the runtime translates it to a long app-private path.
      '';
    };
  };

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
            critical = 15000;
          };
    };
    default = { };
    description = "TermuxPP notify-send timeouts by urgency.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      android-bridge
      (pkgs.callPackage ../../../pkgs/nixpp/android-api.nix {
        inherit inputs;
        notificationTimeouts = config.programs.notify-send.android.timeout;
      })
    ];
    home.sessionVariables.ANDROID_BRIDGE_SOCKET = cfg.socket;
  };
}
