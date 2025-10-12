{
  config,
  lib,
  pkgs,
  ...
}:
let
  snapperConfigs = config.services.snapper.configs or { };

  relevantConfigs = lib.pipe snapperConfigs [
    (lib.mapAttrsToList (
      name: cfg:
      if (cfg ? FSTYPE) && cfg.FSTYPE == "btrfs" && (cfg ? SUBVOLUME) then
        {
          inherit name;
          snapshotDir = "${cfg.SUBVOLUME}/.snapshots";
        }
      else
        null
    ))
    (configs: lib.filter (config: config != null) configs)
  ];

  createSnapshotsSubvolumeScript =
    if relevantConfigs == [ ] then
      null
    else
      pkgs.writeShellScript "snapper-create-snapshots-subvolumes" ''
        set -euo pipefail

        btrfs_bin=${lib.escapeShellArg "${pkgs.btrfs-progs}/bin/btrfs"}

        if [ -n "''${SNAPPER_BTRFS_BIN:-}" ]
        then
          btrfs_bin="$SNAPPER_BTRFS_BIN"
        fi

        configs=(
          ${lib.concatMapStringsSep "\n          " (
            config: lib.escapeShellArg "${config.name}:${config.snapshotDir}"
          ) relevantConfigs}
        )

        for config_info in "''${configs[@]}"
        do
          config_name="''${config_info%%:*}"
          snapshot_dir="''${config_info#*:}"

          if [ -z "$config_name" ] || [ -z "$snapshot_dir" ]
          then
            echo "Skipping snapper config $config_name because the snapshot directory is missing."
            continue
          fi

          echo "Ensuring $snapshot_dir exists for snapper config $config_name..."

          if "$btrfs_bin" subvolume show "$snapshot_dir"
          then
            echo "$snapshot_dir already exists, nothing to do."
            continue
          fi

          echo "Creating $snapshot_dir subvolume for snapper config $config_name..."
          "$btrfs_bin" subvolume create "$snapshot_dir"
        done
      '';
in
{
  services.snapper = {
    snapshotRootOnBoot = false;
    snapshotInterval = "hourly";
    cleanupInterval = "1d";
    persistentTimer = true;

    configs = {
      home = {
        FSTYPE = "btrfs";
        SUBVOLUME = "/home"; # @home won't work here
        ALLOW_USERS = [ config.custom.username ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
    };
  };

  environment.systemPackages = with pkgs; [ snapper-gui ];

  systemd.services.snapperd.serviceConfig.ExecStartPre = lib.mkBefore (
    lib.optional (createSnapshotsSubvolumeScript != null) createSnapshotsSubvolumeScript
  );
}
