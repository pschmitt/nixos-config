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
      export NIX_LAN_MIRROR_S3_ENDPOINT=${lib.escapeShellArg cfg.pins.endpoint}
      export NIX_LAN_MIRROR_S3_REGION=${lib.escapeShellArg cfg.pins.region}
      export NIX_LAN_MIRROR_S3_PROFILE=${lib.escapeShellArg (toString cfg.pins.profile)}
      exec ${
        lib.getExe (pkgs.python3.withPackages (ps: [ ps.boto3 ]))
      } ${./harmonia/scripts/cache-lan-mirror.py} "$@"
    '';
  };
in
{
  options.services.harmonia.lanMirror = {
    enable = lib.mkEnableOption "keeping selected niks3-pinned outputs in the local store for LAN clients";
    pins = {
      bucket = lib.mkOption {
        type = lib.types.str;
        example = "nix-cache";
        description = "The niks3 cache bucket; niks3 stores each pin as the object `pins/<name>`.";
      };
      endpoint = lib.mkOption {
        type = lib.types.str;
        example = "https://s3.example.org";
        description = "S3 endpoint of the bucket.";
      };
      region = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "S3 signing region.";
      };
      profile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "niks3";
        description = "AWS credentials profile (root's shared credentials file) that may read the bucket.";
      };
      prefix = lib.mkOption {
        type = lib.types.str;
        example = "nixbot-owner-repo-";
        description = "Pin name prefix; each target's pin is `<prefix><target>`.";
      };
    };
    minFreeGiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Skip a target if fetching it would leave less than this much space free in the store.";
    };
    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "hosts.ge2" ];
      description = "Pinned targets whose outputs (with closures) are kept locally.";
    };
    trigger = {
      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        example = 8723;
        description = ''
          TCP port on which any connection starts a mirror run (CI connects
          after pinning a new output). The timer keeps polling regardless.
        '';
      };
      allowedAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        # Tailscale and NetBird addresses.
        default = [
          "100.64.0.0/10"
          "fd7a:115c:a1e0::/48"
        ];
        description = "Source addresses allowed to connect to the trigger port.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      # Enforced by the socket itself, not the host firewall. Each connection
      # only starts the mirror; a run already in progress absorbs it.
      sockets.nix-cache-lan-mirror-trigger = lib.mkIf (cfg.trigger.port != null) {
        description = "Start a LAN mirror run on connection";
        wantedBy = [ "sockets.target" ];
        listenStreams = [ (toString cfg.trigger.port) ];
        socketConfig = {
          Accept = true;
          IPAddressAllow = cfg.trigger.allowedAddresses;
          IPAddressDeny = "any";
          MaxConnections = 4;
        };
      };
      services."nix-cache-lan-mirror-trigger@" = lib.mkIf (cfg.trigger.port != null) {
        description = "Start a LAN mirror run";
        serviceConfig.ExecStart = "${config.systemd.package}/bin/systemctl start --no-block nix-cache-lan-mirror.service";
      };
      services.nix-cache-lan-mirror = {
        description = "Mirror niks3-pinned outputs into the local store for LAN clients";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe mirror} ${
            lib.escapeShellArgs (
              [
                cfg.pins.bucket
                cfg.pins.prefix
              ]
              ++ cfg.targets
            )
          }";
          RuntimeMaxSec = "6h";
          Nice = 19;
          IOSchedulingClass = "idle";
          CPUQuota = "100%";
        };
      };
      timers.nix-cache-lan-mirror = {
        wantedBy = [ "timers.target" ];
        # A run without new pins is a few S3 GETs, so poll often to pick up
        # new outputs soon after CI pins them.
        timerConfig = {
          OnBootSec = "10m";
          OnUnitInactiveSec = "5m";
          RandomizedDelaySec = "1m";
        };
      };
    };
  };
}
