# Android devices

| Device | Model (NetBox) | Purpose | Config in `nixos-config/android/` |
|---|---|---|---|
| p11 | Pixel 11 Pro, smartphone | The user's phone. Native Termux with nixpp and yadm, driven by Home Assistant (for example the nightly Termux update script). | `p11.yaml` |
| zf10 | Zenfone 10, smartphone | Phone and a fleet test device for Android apps. | `zf10.yaml` |
| mp4 | Mi Pad 4, tablet | Tablet and a fleet test device for Android apps. | `mp4.yaml` |
| px5 | Pixel 5 (from the `jollyfin` test-device list) | Older test device. Not found in NetBox on the last check. | `px5.yaml` |

`nixos-config/android/` also has `all.yaml` and `imports/*.yaml` (shared app sets: base, devel,
media, banking, iot, ...), plus the `termux-native` and `nixpp` projects.

## What manages what

| Task | Use |
|---|---|
| Talk to a device over ADB: select by serial, shell, push and pull, unlock, enter secrets safely | `adb` skill (private repo) |
| Install, recover or update native Termux (yadm-init, nixpp) on p11, mp4 or zf10 | `termux-init` skill |
| Install or remove apps declaratively (gplay, F-Droid, GitHub releases, local APKs) | `declaroid` (`~/devel/private/pschmitt/declaroid`; read its `AGENTS.md`) with the `android/*.yaml` configs |
| Android app projects (Kotlin, Gradle): jollyfin, nyetbox | Build on a build host (`nix` skill); `just deploy-all` in jollyfin installs a debug build on all test devices |
| Phone settings from Home Assistant (Bluetooth, glove mode, SMS, ADB-driven scripts) | `ha` skill |
| Device purchase data, serials, manuals, device types | `netbox` skill |

Always confirm which phone you are talking to (`adb devices -l`, model and product) before changing
anything, and never assume the first listed device is the intended one.
