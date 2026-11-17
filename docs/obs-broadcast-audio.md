# OBS broadcast audio

An optional route from OBS's ARD, ZDF, and Tagesschau program scenes into
**Meeting Microphone**, alongside the denoised microphone and soundboard.
It is off by default and does not start automatically at login.

## One-time OBS setup

In **Tools → Scripts**, add
`~/.config/obs-studio/scripts/obs-broadcast-audio.lua`.
OBS remembers the script for that scene collection. Add it separately to another
collection if needed. The script does nothing to audio while sharing is off.

Disable existing audio monitoring before enabling this feature. It temporarily
owns OBS's global monitoring device and refuses to start if any source is already
monitored. It restores the previous device and source monitoring modes when
sharing stops. Do not change monitoring settings manually while sharing.

## Controls

```console
obs-broadcast-audio on
obs-broadcast-audio off
obs-broadcast-audio toggle
obs-broadcast-audio status
```

With sharing enabled, only allowlisted visible media/browser sources under the
current **program** scene are monitored: `ARD Live` in `ARD`, `ZDF Live` in `ZDF`,
and `Browser` or `Media` in `Tagesschau`. Preview selection is not used. Nested
scenes and groups are traversed. Hidden items, microphones, desktop capture, VLC
sources, and unrelated overlays are excluded. Browser sources must have
**Control audio via OBS** enabled (already enabled for the current Tagesschau
source). Do not repurpose an allowlisted source for unrelated audio. Renaming a
scene or source requires updating the allowlist in the Lua script.

The route is silent while OBS reports an in-progress transition, rather than
mixing outgoing and incoming broadcasts.

The controller creates a private `OBS Broadcast` null sink, and OBS sends its
monitoring audio there. A PipeWire loopback captures only that sink and is tagged
for the existing WirePlumber Meeting Microphone mixer. It never falls back to
capturing desktop audio. Local speaker playback is not added; existing OBS
streaming and recording audio output is preserved.

Turning sharing off stops the bridge and removes its sink. Losing the OBS script
heartbeat closes the bridge within two seconds; a PipeWire bridge failure stops
the service rather than restarting and silently re-enabling it. A profile or
scene-collection change disarms sharing. OBS shutdown or script unloading also
disarms it. Turn it on explicitly again afterwards.

The meeting app must use **Meeting Microphone**. Muting the physical microphone
with the existing microphone action does **not** mute soundboard or broadcast
audio. The meeting app's own mute silences the complete mix. Noise suppression
in the meeting app may distort music or broadcast audio; use its original-audio
or music mode if available. Audio may lag the OBS virtual camera slightly and
needs a real call/recording check before relying on lip-sync.

## Troubleshooting

`systemctl --user status obs-broadcast-audio.service` shows controller failures.
If enabling reports that the script is unavailable, check that it is loaded in
OBS's active scene collection and inspect **Tools → Scripts → Script Log**.
The script needs OBS's Lua scripting support and `XDG_RUNTIME_DIR` in OBS's
environment.

For an emergency stop, use `obs-broadcast-audio off` or mute the meeting app.
Do not use `soundboard stop`: it stops clip playback, not this bridge.

## Focused tests

On a worker with Python and LuaJIT:

```console
python3 home-manager/gui/test_obs_broadcast_audio.py
mkdir -p "$XDG_RUNTIME_DIR/obs-broadcast-audio"
luajit home-manager/gui/test_obs_broadcast_audio.lua home-manager/gui/obs-broadcast-audio.lua
```

Tests mock OBS and audio commands; they do not transmit audio. End-to-end audio,
OBS Lua bindings, transition timing, and meeting-app processing require a live
OBS session and an explicitly enabled route.
