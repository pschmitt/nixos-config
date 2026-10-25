{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.nix-proprietary-sources;
  # `requireFile` sources cannot be fetched by Nix; the store path each one
  # must have is known at evaluation time.
  sources = map (pkg: {
    inherit (pkg.proprietarySource) name url;
    path = (pkgs.requireFile pkg.proprietarySource).outPath;
  }) cfg.packages;
  seed = pkgs.writeShellApplication {
    name = "nix-proprietary-sources";
    runtimeInputs = [
      config.nix.package
      pkgs.curl
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/nix-proprietary-sources.sh;
  };
in
{
  options.services.nix-proprietary-sources = {
    enable = lib.mkEnableOption "seeding the store with the sources of proprietary packages";
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      description = "Packages whose `proprietarySource` (a `requireFile` source) is kept in the store.";
    };
    netrcFile = lib.mkOption {
      type = lib.types.str;
      description = "Runtime path of a netrc file with credentials for the source URLs.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services.nix-proprietary-sources = {
        description = "Add proprietary package sources to the Nix store";
        # Also on activation, so new or changed sources are seeded right away.
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        environment.NIX_PROPRIETARY_NETRC = cfg.netrcFile;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe seed} ${
            (pkgs.formats.json { }).generate "proprietary-sources.json" sources
          }";
        };
      };
      timers.nix-proprietary-sources = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "5m";
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    };
  };
}
