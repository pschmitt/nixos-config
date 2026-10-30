# Hermes Agent

For live inspection and control, use the configured `home-assistant` MCP server
or the native Home Assistant channel. Hermes does not have `zhj` or local HA
tokens, and `/mnt/ha` may be unavailable because it is an SSHFS mount. Do not
make Hermes startup depend on that mount.

For configuration-file or Lovelace edits, use this fallback order:

1. Check `/mnt/ha` with bounded commands. If it is mounted and responsive,
   read `/mnt/ha/AGENTS.md` and work there.
2. If the mount is absent or stale, try `timeout 30 sudo -n
   hermes-mount-ha`, then re-check the mount with bounded commands. This is a
   narrowly scoped helper that starts only the HA mount unit; do not use broad
   `sudo`, `mount`, or `systemctl` commands.
3. If the mount still cannot be established, work directly on the HA server
   over the configured SSH route (for example through the Home Assistant MCP's
   SSH command capability) under `/homeassistant`, after reading its
   `AGENTS.md`. If that SSH route is unavailable too, report the access failure
   and ask the user to make the repository available.

Never assume an unresponsive `/mnt/ha` is usable: wrap probes such as `stat`,
`findmnt`, and file reads in a timeout.

