# Rclone bisync runtime configuration

The SOPS-managed `rclone/config` file is a seed for the runtime config at
`/var/lib/rclone/rclone.conf`. Each bisync service initializes that file only
when it is absent. Rclone can update its OAuth tokens in the runtime file, and
subsequent service starts preserve those changes. An empty, non-regular, or
symlinked runtime file fails closed. The runtime file is root-owned, mode
`0600`, inside the root-only `/var/lib/rclone` state directory.

Updating the SOPS seed does not rotate the runtime config. For an intentional
rotation, stop the bisync timers, wait for all four bisync services to finish,
and back up the runtime file under
`/mnt/data/backups/rclone/<date>-pre-rotation`. Replace the runtime file from
the current SOPS seed, restore its root ownership and `0600` mode, then start
the timers that were active before rotation. Existing runtime state is never
overwritten automatically.

For the initial migration from the old `/run/secrets/rclone/config` path, stop
both bisync timers and wait for all four bisync services to finish. Back up the
current live config under `/mnt/data/backups/rclone/<date>-pre-migration`, with
directory mode `0700`, root ownership, and file mode `0600`. Compare the live
and backup file hashes without printing either file's contents. Before the
first activation using this module, copy the live config to
`/var/lib/rclone/rclone.conf` only if that persistent file does not already
exist; preserve any existing persistent config instead of overwriting it.
Keep the copied file root-owned and mode `0600`. Restart only the timers that
were active before migration.

The bisync working files and locks remain in `/var/cache/rclone/bisync` and
are separate from this configuration state.
