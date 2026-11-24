# Local Nix store inputs

```sh
rworker setup nix upload-blob "$worker" ./vendor-font.zip
rworker setup nix upload-blob "$worker" --name vendor-tool.tar.gz ./download.tar.gz
just seed-blob "$worker" vendor-font ./vendor-font.zip
```

The upload uses pinned SSH and flat SHA-256 to produce the store path a
fixed-output source expects. Use `--name` to override the basename for a
single file. MCP `setup_nix_upload_blob(name, files, store_name)` reads files
from the MCP host and returns their store paths.

The nixos-config recipe reads `proprietarySource`, verifies the local SHA-256
and uses the package's canonical filename. Run it from the nixos-config
checkout. Imported paths are subject to the worker's normal Nix garbage
collection.

## MCP tools

Use `exec` for a registered job on an existing worker, `exec_ephemeral` for
a one-shot worker with sync and fetch, or `ssh` for a non-interactive command.
`cp` copies files in either direction. `ls`, `jobs` and `events` accept
`watch_seconds`, and `logs` accepts `follow_seconds` and regex filters.
`image_create` and `image_upload` use the MCP host's Nix and OpenStack setup.
Use the CLI for interactive sessions, SSH forwarding and controller
administration. Reconnect MCP clients after an upgrade to load new tools.
