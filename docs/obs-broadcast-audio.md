# OBS broadcast audio

An optional route from OBS's ARD, ZDF, and Tagesschau program scenes into
**Meeting Microphone**, alongside the denoised microphone and soundboard, and
to your own ears: while sharing is on, the broadcast also plays on the current
default audio output (speakers, headphones or a Bluetooth headset).
It is off by default and does not start automatically at login.

## OBS script registration

No manual import is needed. `obs-register-script` adds
`~/.config/obs-studio/scripts/obs-broadcast-audio.lua` to the **active** scene
collection's script list (`modules["scripts-tool"]`) and leaves every other
setting, script and scene untouched. It runs on every Home Manager activation and
before each launch through `obs-hyprland-autostart` (the "OBS Studio (Custom)"
launcher and the autostart unit), `obs-nvidia` and `obs-nvidia-custom`. It is
idempotent and never turns routing on.

OBS rewrites the collection from memory when it exits, so the helper only edits
the file while OBS is **not** running. If OBS is running during an activation,
registration is deferred (the activation log says so) and happens at the next
activation or the next launch through one of the wrappers above. Starting plain
`obs` from the stock launcher does not register; quit OBS and run
`obs-register-script` once, or launch it through a wrapper. Another scene
collection is registered the next time it is the active one at such a moment.

The write is atomic, keeps the file's mode and leaves a private copy of the
previous content next to it (`<collection>.json.obs-register.bak`).
`obs-register-script --check` reports without writing (exit 3 if missing). Its
output never contains scene or script settings.

## Monitoring policy

Existing monitoring on the broadcast sources is fine. While sharing is on, the
script temporarily **owns every allowlisted broadcast source** (`ARD Live`,
`ZDF Live`, `Browser`, `Media`; media or browser sources, in any scene). Before
it touches OBS's global monitoring device it remembers each source's monitoring
mode (and holds a reference to the source), then silences all of them. Only the
visible, allowlisted source on the current program scene is switched to
*Monitor and Output*; every other owned source stays silent, so a source that was
already monitored (for example a saved `ZDF Live` in *Monitor and Output*) can
never leak into the meeting. Renamed or recreated sources are adopted again on
the next pass.

Monitoring on any **unrelated** source (microphone, desktop capture, a VLC
source, ...) is not touched and not allowed: enabling is refused before the
device or any source changes, and the status line says which source it was. If
an unrelated source starts monitoring while sharing runs, sharing stops. Turn
that monitoring off and enable sharing again.

When sharing stops (off, error, profile or scene-collection change, OBS exit,
script unload) the order is fixed so nothing is audible on the sink:
silence all owned sources, restore the original monitoring device, then restore
each source's original monitoring mode and drop the references. If the device
cannot be restored, the sources stay silent and the next pass retries. If OBS
crashes while sharing, the saved modes are lost: the sources stay silent
(modes `None`) and the monitoring device may still be `OBS Broadcast`; restore
them in OBS's audio settings.

OBS calls the frontend callback synchronously from inside its own API (every
scene, monitoring or device change), so the 100 ms tick never nests: a nested
call only requests one more pass, and a lifecycle event or unload during a pass
stops it at the next checkpoint. A failure disarms sharing once (the controller
stops, the status line carries the reason for two seconds) and is logged once
with a traceback, not on every tick.

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
monitoring audio there. Two PipeWire loopbacks capture only that sink (they never
fall back to capturing desktop audio) and start and stop together:

- the **meeting branch**, tagged for the existing WirePlumber Meeting Microphone
  mixer;
- the **local branch**, which plays on your normal default output. It has no
  device name, ID or target in the configuration: the session manager keeps it
  on whatever the default output currently is and moves it when that changes
  (headset connects or disconnects, speakers selected). It is never tagged for
  Meeting Microphone, so what you hear is not mixed into the meeting.
  The stream runs at unity gain; the output device's volume is not touched.

This is the soundboard's model (`soundboard play`): an untargeted local stream
that follows the default output, plus a separate stream tagged
`meeting-mic.feed` that is linked into Meeting Microphone, so the local branch is
audible without sidetone and without hardcoded hardware.

Only loops are refused: if the default output is the `OBS Broadcast` sink (or the
local stream lands on it), both branches stop within half a second and the status
carries the reason. Speakers are allowed. **Acoustic echo:** with speakers,
the broadcast is picked up by your microphone and sent to the meeting a second
time, delayed. Use headphones or keep the volume low during a call; sharing is
not disabled automatically.

Existing OBS streaming and recording audio output is preserved.

Turning sharing off stops both branches and removes the sink. If either branch
exits, both are closed. Leaving an eligible program scene stops both branches.
Losing the OBS script heartbeat closes the bridge within two seconds; a PipeWire bridge failure stops
the service rather than restarting and silently re-enabling it. A profile or
scene-collection change disarms sharing. OBS shutdown or script unloading also
disarms it. Turn it on explicitly again afterwards.

The meeting app must use **Meeting Microphone**. Muting the physical microphone
with the existing microphone action does **not** mute soundboard or broadcast
audio. The meeting app's own mute silences the complete mix. Noise suppression
in the meeting app may distort music or broadcast audio; use its original-audio
or music mode if available. Audio may lag the OBS virtual camera slightly and
needs a real call/recording check before relying on lip-sync.

## Muting or stepping the TV source itself

Muting, unmuting and stepping the volume of the TV source is done by the
native `obs_studio.set_input_mute` and `obs_studio.step_input_volume` actions
of the Home Assistant `obs_studio` integration (the teams-live `/tv` webhooks
call them), independent of the broadcast route above. The scene-to-input
allowlist (`ARD Live` in `ARD`, `ZDF Live` in `ZDF`, `Browser` or `Media` in
`Tagesschau`) lives in the Home Assistant automations. With any other scene on
air (for example brb) they fail without touching OBS. Volume steps are 3 dB
within -40 dB .. 0 dB, `up` also unmutes (even at 0 dB) and `down` never
changes the mute state. Microphones, desktop capture, monitoring and the OBS
Broadcast bridge are never touched.

## Troubleshooting

`systemctl --user status obs-broadcast-audio.service` shows controller failures.
If enabling reports that the script is unavailable, check that
`obs-register-script --check` reports it as registered (registration is
deferred while OBS runs) and inspect **Tools → Scripts → Script Log**.
The script needs OBS's Lua scripting support and `XDG_RUNTIME_DIR` in OBS's
environment.

For an emergency stop, use `obs-broadcast-audio off` or mute the meeting app.
Do not use `soundboard stop`: it stops clip playback, not this bridge.

## Transitions

Leaving the program scene silences the sources first and never touches the OBS
monitoring device, and the controller closes both branches in one step: the
local monitor is signalled first and nothing waits for the meeting branch. What
is already in flight (the device buffer of the headset or speakers) cannot be
recalled, so a very short tail on the current default output remains possible.

Turning sharing off, or any failure, silences every owned source, restores the
original monitoring device, and only then restores each source's saved
monitoring mode. If a source was saved as Monitor and Output on OBS's
`Default` device, that is your own configuration returning, and it is audible
on whatever device OBS resolves `Default` to (not necessarily the current
system default output). The script never changes that configuration; if the
TV sources should not be audible after sharing, set their monitoring to Off in
OBS before enabling sharing.

## Focused tests

On a worker with Python and LuaJIT:

```console
python3 home-manager/gui/test_obs_broadcast_audio.py
python3 home-manager/gui/test_obs_register_script.py
mkdir -p "$XDG_RUNTIME_DIR/obs-broadcast-audio"
luajit home-manager/gui/test_obs_broadcast_audio.lua home-manager/gui/obs-broadcast-audio.lua
```

The Lua test mocks OBS with reference counts, synchronous reentrant callbacks
inside every monitoring and device change, a spill detector (anything audible
on the sink that is not the permitted program source fails the run), preexisting
monitoring modes, an unrelated conflict, source rename and recreation, failure,
restore-retry, unload, and a tail scenario: sources keep playing while the
program leaves them, and at no call may one be audible on the user's output or
on the sink outside the program scene, nor the original device return under an
audible source. The Python tests cover both branches' commands (no
target or tag on the local one), their joint lifecycle (local branch stopped first) and loop detection. On an
isolated worker, `test_obs_broadcast_audio_graph.py` builds a private PipeWire
session and checks the real links: meeting feed to `meeting_source` only, local
branch to the default output and following it, a bounded stop of both branches, no capture fallback. Tests mock
OBS and audio commands; they do not transmit audio. End-to-end audio, OBS Lua bindings, transition
timing, and meeting-app processing require a live OBS session and an explicitly enabled
route.
