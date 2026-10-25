{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.harmonia.publication;
  retain = pkgs.writeShellApplication {
    name = "nix-cache-retain";
    runtimeInputs = [ config.nix.package ];
    text = ''
      export NIX_BIN=${config.nix.package}/bin/nix
      exec ${lib.getExe pkgs.python3} ${./harmonia/scripts/cache-retain.py} "$@"
    '';
  };
  populate = pkgs.writeShellApplication {
    name = "nix-cache-populate";
    runtimeInputs = [
      config.nix.package
      pkgs.bash
      pkgs.git
      pkgs.jq
      pkgs.openssh
    ];
    text = ''
      export NIX_BIN=${config.nix.package}/bin/nix
      export NIX_CACHE_HTTP_URL=https://cache.${config.networking.hostName}.${config.domains.main}
      export NIX_CACHE_RETAIN=${lib.getExe retain}
      export NIX_CACHE_SIGN_KEY=${config.sops.secrets."nix/store/privkey".path}
      export NIX_CACHE_REPLICA=${lib.escapeShellArg "nix-remote-builder@${cfg.replicaHost}"}
      export NIX_SSHOPTS="-i ${
        config.sops.secrets."ssh/nix-remote-builder/privkey".path
      } -oBatchMode=yes -oConnectTimeout=10"
      exec ${lib.getExe pkgs.python3} ${./harmonia/scripts/cache-populate.py} ${pkgs.hello}
    '';
  };
  mirror = cfg.s3Mirror;
in
{
  options.services.harmonia.publication = {
    enable = lib.mkEnableOption "retained CI publications in the Harmonia store";
    populate = lib.mkEnableOption "bounded main-branch cache population and replication";
    replicaHost = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "SSH hostname of the replica (using the existing remote-builder key).";
    };
    s3Mirror = {
      enable = lib.mkEnableOption "mirroring retained main outputs to a niks3 S3 cache";
      package = lib.mkPackageOption pkgs "niks3" { };
      serverUrl = lib.mkOption {
        type = lib.types.str;
        description = "URL of the niks3 server.";
      };
      authTokenFile = lib.mkOption {
        type = lib.types.str;
        description = "Runtime path of a niks3 token allowed to push and manage `main-*` pins.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.populate || cfg.replicaHost != "";
        message = "Cache population requires a replica host.";
      }
    ];
    environment.systemPackages = [ retain ];
    users.groups.nix-cache-publishers.members = [
      "github-actions"
      "nix-remote-builder"
      config.mainUser.username
    ];
    systemd = {
      tmpfiles.rules = [
        "d /nix/var/nix/gcroots/nixos-config 2775 root nix-cache-publishers - -"
        "d /var/lib/nixos-config-cache 2775 root nix-cache-publishers - -"
      ];
      services = {
        nix-cache-retention = {
          description = "Expire old PR cache roots, retaining current main outputs";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe retain} prune";
          };
        };
        nix-cache-s3-sync = lib.mkIf mirror.enable {
          description = "Mirror retained main outputs to the niks3 S3 cache";
          wants = [ "network-online.target" ];
          after = [ "network-online.target" ];
          restartIfChanged = false;
          environment = {
            NIKS3_BIN = lib.getExe' mirror.package "niks3";
            NIKS3_SERVER_URL = mirror.serverUrl;
            NIKS3_AUTH_TOKEN_FILE = mirror.authTokenFile;
          };
          serviceConfig = {
            Type = "oneshot";
            # Path-triggered runs only push targets whose outputs changed.
            # Let a burst of publications (and their atomic renames) land.
            ExecStartPre = "${lib.getExe' pkgs.coreutils "sleep"} 60";
            ExecStart = "${lib.getExe retain} s3-sync";
            StateDirectory = "nixos-config-cache-s3";
            RuntimeMaxSec = "12h";
            Nice = 15;
            IOSchedulingClass = "idle";
            CPUQuota = "200%";
          };
        };
        nix-cache-s3-sync-all = lib.mkIf mirror.enable {
          description = "Re-check every retained main output in the niks3 S3 cache";
          inherit (config.systemd.services.nix-cache-s3-sync)
            wants
            after
            restartIfChanged
            environment
            ;
          serviceConfig = config.systemd.services.nix-cache-s3-sync.serviceConfig // {
            ExecStartPre = [ ];
            ExecStart = "${lib.getExe retain} s3-sync --all";
          };
        };
        nix-cache-populate = lib.mkIf cfg.populate {
          description = "Populate and replicate main outputs and verify Harmonia delivery";
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "harmonia.service"
          ];
          # Run independently of nixos-rebuild's activation jobs. A long cache
          # pass must not hold a system switch open until every build finishes.
          restartIfChanged = false;
          environment.NIX_CONFIG = "accept-flake-config = true";
          serviceConfig = {
            Type = "exec";
            ExecStart = lib.getExe populate;
            StateDirectory = "nixos-config-cache-populate";
            RuntimeMaxSec = "4h";
            Nice = 15;
            IOSchedulingClass = "idle";
            CPUQuota = "200%";
            MemoryHigh = "50%";
          };
        };
      };
      # CI and nix-cache-populate publish over SSH; mirror asynchronously
      # instead of holding their sessions open during uploads.
      paths.nix-cache-s3-sync = lib.mkIf mirror.enable {
        wantedBy = [ "paths.target" ];
        pathConfig.PathChanged = "/var/lib/nixos-config-cache/main";
      };
      timers = {
        nix-cache-s3-sync-all = lib.mkIf mirror.enable {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "daily";
            RandomizedDelaySec = "1h";
            Persistent = true;
          };
        };
        nix-cache-retention = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            Persistent = true;
          };
        };
        nix-cache-populate = lib.mkIf cfg.populate {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "15m";
            OnUnitInactiveSec = "15m";
            RandomizedDelaySec = "5m";
          };
        };
      };
    };
  };
}
