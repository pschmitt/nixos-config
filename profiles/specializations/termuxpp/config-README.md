# ~/.config/termuxpp

Everything in this directory is written by Home Manager (nixos-config,
`profiles/specializations/termuxpp`) on every activation. Do not edit it here
or in the app's properties editor: the next activation overwrites the changes.
Change the Nix configuration instead.

## Why copies and not links to /nix/store

The TermuxPP app reads these files itself, from Android, outside the Nix guest.
The guest's `/nix/store` exists only inside the guest's mount namespace; from
the app's side a symlink into `/nix/store` points nowhere. So the files are
installed as regular files (`install -m ...`), not linked like other Home
Manager files.

`termuxpp.properties` is also not a static file: the ADB shell Wi-Fi
allow-list (`adb-shell-allowed-ssids`) is read from a SOPS secret at
activation, so the network names never enter the Nix store.

## What is here

| File | Managed by |
| --- | --- |
| `termuxpp.properties` | `fullNix.properties` and `fullNix.adbShell` (`modules/home-manager/termuxpp/properties.nix`) |
| `colors.properties`, `font.ttf` | `modules/home-manager/termuxpp/appearance.nix` |
| `bin/termux-file-editor` | opens shared files in the guest's nvim |
| `bin/termux-url-opener` | handles shared URLs |
| `README.md` | this file |
