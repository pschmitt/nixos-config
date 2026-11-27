# Guest launcher updates

A generation ships the guest's seccomp launcher as `native/launcher`
(`system.nativeLauncher`); after a switch the daemon replaces
`runtime/launcher` with it. Every running guest process carries a seccomp
filter that exempts the launcher's syscall stub by address and survives
`execve`, so a new launcher is started under the old filter on every exec.
Its stub must therefore sit where the runtime's original launcher had it:
`system.launcherStub` per host (default `0x1000005690`; p11 `0x10000056e0`),
built with termuxpp's `launcher.withStub`. For a newly enrolled host, read the
address with `nm` on the runtime's launcher (`allow_start`) before shipping a
launcher.

The daemon installs a candidate only after it ran busybox on its own and when
exec'd under the current launcher; otherwise it logs "kept the current
launcher". A launcher with a moved stub kills every new process with SIGSYS
("invalid system call") while the daemon and existing sessions keep running.

## Recover a broken launcher

Symptoms: every new guest program dies with "invalid system call", sshd is
gone and `svc supervise` restarts in a loop. An open guest session still runs
zsh builtins, so put the APK's launcher back without starting a program
(`zsh/files` has no `cp`):

```zsh
zmodload zsh/files zsh/mapfile &&
  mapfile[/run/nixpp-runtime/.l]=$mapfile[/android/data/data/dev.pschmitt.termux/files/usr/share/nixpp/launcher] &&
  chmod 700 /run/nixpp-runtime/.l &&
  mv -f /run/nixpp-runtime/.l /run/nixpp-runtime/launcher
```

Without SSH, type it into the app's terminal with
`adb shell "input text '...'"` (spaces as `%s`, one line) and read the result
from `adb exec-out screencap -p`. Then switch to a generation whose
`native/launcher` fits; otherwise the next daemon start installs the broken
one again.
