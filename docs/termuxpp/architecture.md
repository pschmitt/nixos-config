# TermuxPP architecture and redesign

How the pieces of a TermuxPP phone fit together, what kept breaking, and the
redesign that addresses it. [system.md](system.md) documents the commands;
this page is the map.

## Layers

```
Android (kernel, Settings, Shizuku)
  | kills app child processes beyond a device-wide limit (phantom killer)
  v
TermuxPP app (Java, one app UID)
  - TermuxService: foreground service, owns the lifetime of everything below
  - terminal UI, Termux:API, termux-am socket server, mTLS ADB shell
  - publishers: network.json, permissions.json (runtime directory)
  - controller watchdog
  | starts (ProcessBuilder)
  v
Outer: native Android userland (bionic)
  - $PREFIX: Termux packages (termux-am, termux-api helpers, ...)
  - nixpp controller ("nixpp serve"): nixpp.sock (switch, prepare,
    recover) and outer.sock (run a native command for the guest)
  | launcher (seccomp path rewriting, re-exec, bind table)
  v
Inner: Nix guest (glibc, Home Manager)
  - user tools, nixpp guest commands
  - svc supervise -> runit -> guest services (sshd :2222, ...)
  - android-bridge <-> app
```

Crossing the boundary:

- App to guest: a terminal session runs `nixpp login`; SSH reaches the guest
  sshd; the ADB shell connects to the app over mTLS.
- Guest to Android: Termux:API broadcasts (`termux-*`), the guest's
  `termux-am` (same UID as the app, so non-exported components work),
  `xdg-open`, the android bridge.
- Guest to the native userland: `nixpp enter --outer` and `rish` through
  `outer.sock`.

## What kept breaking

| Symptom | Cause |
| --- | --- |
| `nixpp: cannot reach the native controller` | The controller is an app child process. Android's phantom process killer trimmed it, and nothing restarted it until the app process restarted. |
| `CANNOT LINK EXECUTABLE ... libtermux-pkg-redirect.so not found` | Native processes kept the APK's library directory (`/data/app/~~hash/...`) in `LD_PRELOAD`. Every APK update removes that directory. |
| SSH lands outside the guest | A native Termux sshd from the native bundle era shared port 2222 with the guest sshd and was started by termux-services' runsvdir. |
| Leftover processes survive app restarts | Processes started through `run-as` (debug builds) run in another SELinux context; `am force-stop` does not reach them. |
| Native `termux-am` fails | Stock `termux-am-socket` has `files/apps/com.termux/...` compiled in; the redirect library rewrote only the data directory. |
| `rish` loses output | Without a terminal it exits before the remote output arrives. |

## Principles

Derived from these failures and from
[droid-nix](https://github.com/lassulus/droid-nix), which avoids most of them
by having fewer moving parts (no native controller, one in-app socket, no
`LD_PRELOAD`), but supervises nothing and does not survive APK updates.

1. **The app owns every long-running process.** `TermuxService` starts them,
   checks them and restarts them. Nothing long-running starts from `run-as`,
   a Tasker script or a login shell's profile.
2. **No path that changes on APK updates in a running process.** Processes
   reference stable paths in the app's data directory; the app refreshes
   those on start.
3. **One entry path into the guest.** Terminal, SSH, ADB shell and Tasker all
   go through the same login with the same environment.
4. **One sshd, in the guest.** The native userland runs no network services.
5. **Assume Android kills processes.** Disable the child process limit where
   possible (`termuxpp-setup-permissions grant processes`), and make restarts
   cheap and automatic where not.

## Steps

| Step | Status |
| --- | --- |
| Controller watchdog in `TermuxService` (restart when `nixpp.sock` stops answering, backoff) | Done (termux-app 40597fae) |
| Child process limit in `termuxpp-setup-permissions`; disabled on the phones | Done |
| Stable redirect library: the app installs `files/lib/libtermux-pkg-redirect.so` atomically; shells, start scripts, `nixpp native-shell` and the ADB shell use it; the `apk-library` marker points at it, so APK updates no longer restart nixpp processes | In progress |
| Redirect library maps `files/apps/com.termux` to the fork, fixing stock `termux-am-socket` | In progress |
| Native sshd off (runit `down` file from guest activation) | Done (2d128ebd) |
| One app-owned native supervisor: the controller, the guest service manager and the android bridge run as children of one process the app watches, instead of separately started processes | Planned |
| Single login path for terminal, SSH, ADB shell and Tasker | Planned |
| No long-running `run-as` processes; `run-as` only for one-shot recovery | Planned |
