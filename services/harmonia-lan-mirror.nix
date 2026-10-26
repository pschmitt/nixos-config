{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.harmonia.lanMirror;
  mirror = pkgs.writeShellApplication {
    name = "nix-cache-lan-mirror";
    runtimeInputs = [ config.nix.package ];
    text = ''
      export NIX_STORE_BIN=${config.nix.package}/bin/nix-store
      export NIX_LAN_MIRROR_MIN_FREE=${toString (cfg.minFreeGiB * 1024 * 1024 * 1024)}
      exec ${lib.getExe pkgs.python3} ${./harmonia/scripts/cache-lan-mirror.py} "$@"
    '';
  };
in
{
  options.services.harmonia.lanMirror = {
    enable = lib.mkEnableOption "keeping selected main outputs built by nixbot in the local store for LAN clients";
    sourceUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://nixbot.example.org/nix-outputs/github/owner/repo/main";
      description = "nixbot's published outputs of a repository's default branch (one store path per attribute).";
    };
    minFreeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Skip a target if fetching it would leave less than this much space free in the store.";
    };
    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "herculesCI.onPush.default.outputs.hosts.ge2" ];
      description = "nixbot attributes whose outputs (with closures) are kept locally.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services.nix-cache-lan-mirror = {
        description = "Mirror nixbot's main outputs into the local store for LAN clients";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe mirror} ${lib.escapeShellArgs ([ cfg.sourceUrl ] ++ cfg.targets)}";
          RuntimeMaxSec = "6h";
          Nice = 19;
          IOSchedulingClass = "idle";
          CPUQuota = "100%";
        };
      };
      timers.nix-cache-lan-mirror = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "10m";
          OnUnitInactiveSec = "30m";
          RandomizedDelaySec = "5m";
        };
      };
    };
  };
}
