# Syncthing Nautilus

`syncthing-nautilus` is a small `nautilus-python` extension which adds local
Syncthing status emblems to local files and directories. It uses only Python's
standard library for the Syncthing client; it does not require Syncthing-GTK.

## Design

Nautilus asks extensions about many files during a directory listing, so this
extension never makes a REST request from the Nautilus UI thread and never
makes one request per file. It discovers Syncthing folders once, then a single
background refresh for each visible folder requests:

- `GET /rest/db/status` for aggregate state and counts;
- `GET /rest/db/need` for a batched set of locally-needed paths; and
- `GET /rest/folder/errors` for paths with current pull or scan errors.

The REST Events endpoint is held open in a background worker. Any event
invalidates cached snapshots, causing visible files to be refreshed without a
Nautilus restart. A 30-second TTL is the fallback if the event endpoint is not
available. HTTP timeouts are short, failures are cached briefly, and an absent
or stopped Syncthing instance results in no emblems rather than UI stalls.

Syncthing's exact `GET /rest/db/file` endpoint is per file. Using it while
Nautilus enumerates a directory would be unsafe, so this extension deliberately
does not. Therefore, while a folder is out of sync, only paths returned by the
batched `db/need` and `folder/errors` calls get a precise per-item state.
Unlisted files are left unmarked (`unknown`) instead of being incorrectly shown
as synced. Directories containing a listed pending/error descendant get the
corresponding status, and the folder root always reflects aggregate work.

## Statuses and emblems

| State | Meaning | Standard icon name |
| --- | --- | --- |
| synced | Folder has no pending work or errors | `emblem-synchronized` |
| syncing | Listed as needed, or a directory contains a needed path | `sync-synchronizing` |
| error | Listed Syncthing error, or folder-root pull error | `sync-error` |
| conflict | Filename contains `.sync-conflict-` | `emblem-important` |
| unknown | Out of sync but not present in the bounded batch response | no emblem |

These names are specified by the [Freedesktop icon naming
specification](https://specifications.freedesktop.org/icon-naming/latest/).
Themes can still choose not to draw a particular standard icon.

## Discovery and security

The extension reads the first usable `config.xml` from, in order:

1. `$SYNCTHING_CONFIG_DIR`, `$STCONFDIR`, or `$STHOMEDIR`;
2. `$XDG_STATE_HOME/syncthing` or `~/.local/state/syncthing`;
3. `$XDG_CONFIG_HOME/syncthing` or `~/.config/syncthing`.

This follows Syncthing's current and legacy configuration locations. It reads
folder paths, the local GUI address and its API key from the file. The following
optional overrides are supported:

```text
SYNCTHING_CONFIG_DIR=/path/to/syncthing
SYNCTHING_URL=http://127.0.0.1:8384
SYNCTHING_API_KEY=...
SYNCTHING_NAUTILUS_DEBUG=1
```

`SYNCTHING_URL` must be an `http` or `https` loopback URL (`localhost`,
`127.0.0.1`, or `::1`); non-local URLs are rejected. The key is sent only as
the `X-API-Key` request header, never logged. For HTTPS discovered from
`config.xml`, a local `https-cert.pem` is used as the trust root when present;
the extension never disables certificate verification. UNIX-socket GUI
addresses are intentionally unsupported in this initial version.

## NixOS / Home Manager installation

This repository exposes the package as `syncthing-nautilus`.

```nix
environment.systemPackages = [
  pkgs.nautilus
  pkgs.nautilus-python
  pkgs.syncthing-nautilus
];
```

For a single desktop user, Home Manager is normally more appropriate:

```nix
home.packages = [
  pkgs.nautilus
  pkgs.nautilus-python
  pkgs.syncthing-nautilus
];
```

The package installs its loader at
`share/nautilus-python/extensions/syncthing_status.py`, a current standard
`nautilus-python` extension location. It does not modify the home directory
during the build or installation.

After installing or updating the extension, restart Nautilus:

```sh
nautilus -q
nautilus &
```

`nautilus-python` loads extensions from `$XDG_DATA_DIRS/nautilus-python/extensions`.
To diagnose loading, start Nautilus from a terminal with:

```sh
NAUTILUS_PYTHON_DEBUG=misc SYNCTHING_NAUTILUS_DEBUG=1 nautilus --new-window
```

For an already desktop-launched Nautilus, inspect its user-session log:

```sh
journalctl --user -b /usr/bin/nautilus
```

The relevant API contracts are documented by Syncthing for
[`db/file` and other REST calls](https://docs.syncthing.net/dev/rest.html),
[`db/need`](https://docs.syncthing.net/rest/db-need-get.html),
[`db/status`](https://docs.syncthing.net/rest/db-status-get),
[`folder/errors`](https://docs.syncthing.net/rest/folder-errors-get.html), and
[long-polling events](https://docs.syncthing.net/rest/events-get.html).
