# The native prefix (outer layer)

The app's native prefix (`/data/data/dev.pschmitt.termux/files/usr`) is the
slim outer environment: TermuxPP's own files only, no Termux packages, no
bash, no dpkg or APT. Everything else lives in the Nix guest. Native scripts
run under Android's `/system/bin/sh` (`bin/sh` links to it), with
`/system/bin` on `PATH` for tools such as `pm`.

| Path | Owner |
| --- | --- |
| `bin/nixpp` | nixpp (the generation's `native/nixpp`) |
| `bin/nixpp-setup`, `bin/rbw`, `bin/rbw-agent`, `share/nixpp/*`, `share/licenses/rbw/LICENSE`, `etc/nixpp/setup.conf` | nixpp prefix sync (`system.nativePrefix`) |
| `bin/tpp` (link into the APK), `share/tpp/*`, the three tpp completions, `libexec/termux-api*`, `libexec/termux-callback`, `etc/termux/termux.env`, `var/lib/tpp/*` | the app |
| `etc/tls/cert.pem`, `bin/sh` | the bootstrap |

## How it stays current

Nothing in the prefix needs a reinstall or `apt`. After a switch, nixpp's
daemon installs the generation's `native/nixpp`, `native/launcher` (after a
smoke test, alone and under the current launcher), `bootstrap/{busybox,nix}`
and the `native/prefix.json` files. A prefix file is replaced only if it is
absent, identical, or unchanged since nixpp last installed it (record:
`$PREFIX/var/lib/nixpp/prefix-install.json`); the bootstrap's first copy is
kept as `<file>.nixpp.bak`, and a file changed by hand is left alone and
logged. The daemon's log is `/run/nixpp-runtime/system-control.log` in the
guest. A prefix file in `system.nativePrefix` must work without bash: give
scripts a `#!/system/bin/sh` shebang.

`tpp --outer ARGS` in the guest runs the APK's native `tpp` (what
`bin/tpp` links to): the single tpp to update is the app's.

## Slim an old prefix in place

A phone enrolled with the old upstream-based bootstrap still has the Termux
packages in its prefix. Clearing the app's data would wipe the whole guest
(several GB of store and home); instead prune the prefix in place, with the
device claim held:

1. Back up the prefix and the native dotfiles that point into it to the
   workstation: from the guest,
   `cd /data/data/dev.pschmitt.termux/files && tar -cf - --exclude=usr/tmp usr home/.termux home/.config/termux home/.config/termuxpp home/bin`
   piped over SSH into `zstd` under `~/Backups/termuxpp/HOST/` (mode 0600).
2. Check what still runs from the prefix (only `nixpp` should:
   `readlink /proc/*/exe`), and which native-home links point into it:
   `shell` in `~/.termux`, `~/.config/termux` and `~/.config/termuxpp`
   (a dangling one breaks `tpp-adb-shell`), old yadm helpers in `~/bin` with a prefix bash shebang.
3. Move every prefix file outside the table above into
   `files/usr.pruned` (same filesystem, so `mv` is a rename), delete empty
   directories, recreate `bin`, `lib`, `tmp` and link `bin/sh` to
   `/system/bin/sh`. Move the stale native-home links aside too. Moving about
   30,000 files through the guest takes 20 to 30 minutes: run it in the
   background.
4. Restart the native controller if its environment still preloads a
   pruned library: a controller first started from an old Termux login keeps
   `LD_PRELOAD=…/usr/lib/libtermux-exec.so` across its self-restarts, and
   every native command then fails with `CANNOT LINK EXECUTABLE
   "/system/bin/sh"` (a switch fails its candidate check). Check with
   `tr '\0' '\n' < /proc/PID/environ | grep LD_PRELOAD` for the
   `nixpp --runtime … serve` process; kill it, and the app's watchdog
   starts a clean one within about two minutes (SSH drops meanwhile). nixpp
   from termuxpp c6e55734 on drops missing preload entries itself.
5. Verify: a new app session enters the guest, SSH works, `nixpp status`,
   `tpp battery`, `tpp-adb-shell -- true`, and the daemon log shows no new
   errors after the next switch. Then delete `files/usr.pruned`.
