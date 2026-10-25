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
    runtimeInputs = [
      config.nix.package
      pkgs.openssh
    ];
    text = ''
      export NIX_STORE_BIN=${config.nix.package}/bin/nix-store
      export NIX_LAN_MIRROR_MIN_FREE=${toString (cfg.minFreeGiB * 1024 * 1024 * 1024)}
      export NIX_LAN_MIRROR_SSH=${lib.escapeShellArg "ssh -i ${cfg.sshKeyFile} -oBatchMode=yes -oConnectTimeout=10"}
      exec ${lib.getExe pkgs.python3} ${./harmonia/scripts/cache-lan-mirror.py} "$@"
    '';
  };
in
{
  options.services.harmonia.lanMirror = {
    enable = lib.mkEnableOption "keeping selected retained main outputs in the local store for LAN clients";
    sourceHost = lib.mkOption {
      type = lib.types.str;
      example = "nix-remote-builder@rofl-14.example.org";
      description = "SSH destination of the cache host that runs `nix-cache-retain`.";
    };
    sshKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Runtime path of the SSH key for `sourceHost`.";
    };
    minFreeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Skip a target if fetching it would leave less than this much space free in the store.";
    };
    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "nixosConfigurations.ge2.config.system.build.toplevel" ];
      description = "Retained main targets whose outputs (with closures) are kept locally.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services.nix-cache-lan-mirror = {
        description = "Mirror retained main outputs into the local store for LAN clients";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe mirror} ${lib.escapeShellArgs ([ cfg.sourceHost ] ++ cfg.targets)}";
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
