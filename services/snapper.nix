{ config, lib, modulesPath, pkgs, ... }:
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

  createSnapshotsSubvolumeScripts =
    lib.forEach relevantConfigs (
      configInfo:
        pkgs.writeShellScript "snapper-create-${configInfo.name}-snapshots-subvolume" ''
          # shellcheck shell=bash
          set -euo pipefail

          btrfs_bin=${lib.escapeShellArg "${pkgs.btrfs-progs}/bin/btrfs"}

          if [ -n "''${SNAPPER_BTRFS_BIN:-}" ]
          then
            btrfs_bin="$SNAPPER_BTRFS_BIN"
          fi

          config_name=${lib.escapeShellArg configInfo.name}
          snapshot_dir=${lib.escapeShellArg configInfo.snapshotDir}

          if "$btrfs_bin" subvolume show "$snapshot_dir"
          then
            exit 0
          fi

          echo "Creating $snapshot_dir subvolume for snapper config $config_name..."
          "$btrfs_bin" subvolume create "$snapshot_dir"
        ''
    );

  snapperWrappers =
    lib.mapAttrsToList (
      name: _:
        pkgs.writeShellScriptBin "snapper-${name}" ''
          exec ${lib.escapeShellArg "${pkgs.snapper}/bin/snapper"} -c ${lib.escapeShellArg name} "$@"
        ''
    ) snapperConfigs;
in
{
  imports = [ "${modulesPath}/services/misc/snapper.nix" ];

  environment.systemPackages = snapperWrappers;

  systemd.services.snapperd.serviceConfig.ExecStartPre =
    lib.mkBefore (
      lib.optionals (createSnapshotsSubvolumeScripts != [ ])
        createSnapshotsSubvolumeScripts
    );
}
