{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.services.recyclarr = {
    sonarrInstances = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Sonarr instance configurations contributed by sonarr.nix.";
    };
    radarrInstances = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Radarr instance configurations contributed by radarr.nix.";
    };
  };

  config =
    let
      cfg = config.services.recyclarr;
      hasAny = cfg.sonarrInstances != { } || cfg.radarrInstances != { };
    in
    lib.mkIf hasAny {
      sops.templates."recyclarr.yml" = {
        mode = "0400";
        content = builtins.toJSON (
          lib.optionalAttrs (cfg.sonarrInstances != { }) { sonarr = cfg.sonarrInstances; }
          // lib.optionalAttrs (cfg.radarrInstances != { }) { radarr = cfg.radarrInstances; }
        );
      };

      systemd.services.recyclarr = {
        description = "Recyclarr TRaSH-guides sync";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.recyclarr}/bin/recyclarr sync --config ${
            config.sops.templates."recyclarr.yml".path
          }";
          StateDirectory = "recyclarr";
          Environment = "RECYCLARR_APP_DATA=/var/lib/recyclarr";
        };
      };

      systemd.timers.recyclarr = {
        description = "Periodic recyclarr TRaSH-guides sync";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
    };
}
