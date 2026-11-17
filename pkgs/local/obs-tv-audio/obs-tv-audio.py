#!/usr/bin/env python3
"""Mute or step the volume of the ARD / ZDF / Tagesschau OBS sources.

Counterpart of the obs-broadcast-audio Lua allowlist: the only sources this
tool ever touches are the allowlisted media/browser sources that are visible
under the current *program* scene (nested scenes and groups included). It
never touches microphones, desktop capture, other scenes' sources, the
monitoring routing or the OBS Broadcast bridge.

  mute                 explicitly mute (never toggle, never unmute)
  volume up|down       step by --step-db, clamped to [MIN_DB, MAX_DB]; never
                       touches the mute state, never boosts above 0 dB
  status               read-only: scene, sources, mute state and dB

Exit status: 0 done, 1 error, 3 no active TV source (nothing was changed).
Connection settings follow obs-control: OBS_API_HOST, OBS_API_PORT (default
localhost:6277), OBS_API_PASSWORD, else the password file. The password is
never printed.
"""

import argparse
import os
import re
import sys

# Mirrors scenes{} in home-manager/gui/obs-broadcast-audio.lua.
SCENES = {
    "ARD": frozenset({"ARD Live"}),
    "ZDF": frozenset({"ZDF Live"}),
    "Tagesschau": frozenset({"Browser", "Media"}),
}
KINDS = frozenset({"ffmpeg_source", "browser_source"})

MIN_DB = -40.0
MAX_DB = 0.0
DEFAULT_STEP_DB = 3.0
MAX_STEP_DB = 6.0
MAX_DEPTH = 8

EXIT_ERROR = 1
EXIT_NO_SOURCE = 3


class TvAudioError(Exception):
    pass


def unversioned(kind):
    return re.sub(r"_v\d+$", "", kind or "")


def read_password():
    password = os.environ.get("OBS_API_PASSWORD")
    if password:
        return password
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.join(
        os.path.expanduser("~"), ".config"
    )
    path = os.environ.get("OBS_PASSWORD_FILE") or os.path.join(
        config, "obs-studio", "obs-websocket.password"
    )
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def connect():
    import obsws_python as obs

    return obs.ReqClient(
        host=os.environ.get("OBS_API_HOST", "localhost"),
        port=int(os.environ.get("OBS_API_PORT", "6277")),
        password=read_password(),
        timeout=5,
    )


def collect(client, scene, allowed, found, visited, depth=0, group=False):
    """Walk the visible items of a scene or group, gathering allowlisted sources."""
    if scene in visited or depth > MAX_DEPTH:
        return
    visited.add(scene)
    lister = client.get_group_scene_item_list if group else client.get_scene_item_list
    for item in lister(scene).scene_items:
        if not item.get("sceneItemEnabled"):
            continue
        name = item.get("sourceName")
        kind = item.get("inputKind")
        if item.get("isGroup"):
            collect(client, name, allowed, found, visited, depth + 1, group=True)
        elif kind is None:
            collect(client, name, allowed, found, visited, depth + 1)
        elif name in allowed and unversioned(kind) in KINDS and name not in found:
            found.append(name)


def active_sources(client):
    scene = client.get_current_program_scene().current_program_scene_name
    allowed = SCENES.get(scene)
    if not allowed:
        return scene, []
    found = []
    collect(client, scene, allowed, found, set())
    return scene, found


def clamp_step(current_db, direction, step_db):
    """Next dB value: bounded, monotonic in the requested direction."""
    current_db = max(current_db, -100.0)
    if direction == "up":
        if current_db >= MAX_DB:
            return current_db
        return min(current_db + step_db, MAX_DB)
    if current_db <= MIN_DB:
        return current_db
    return max(current_db - step_db, MIN_DB)


def do_status(client, scene, sources, out):
    print(f"scene: {scene}", file=out)
    for name in sources:
        muted = client.get_input_mute(name).input_muted
        volume = client.get_input_volume(name).input_volume_db
        print(f"{name}: muted={str(bool(muted)).lower()} db={volume:.1f}", file=out)


def do_mute(client, sources, out):
    for name in sources:
        client.set_input_mute(name, True)
    for name in sources:
        if not client.get_input_mute(name).input_muted:
            raise TvAudioError(f"{name} did not report muted")
    print(f"muted {len(sources)} source(s)", file=out)


def do_volume(client, sources, direction, step_db, out):
    for name in sources:
        current = client.get_input_volume(name).input_volume_db
        target = clamp_step(float(current), direction, step_db)
        if target != current:
            client.set_input_volume(name, vol_db=target)
        print(f"{name}: {current:.1f} -> {target:.1f} dB", file=out)


def step_value(text):
    value = float(text)
    if not 0 < value <= MAX_STEP_DB:
        raise argparse.ArgumentTypeError(f"step must be in (0, {MAX_STEP_DB:g}] dB")
    return value


def parser():
    cli = argparse.ArgumentParser(prog="obs-tv-audio", description=__doc__.split("\n")[0])
    sub = cli.add_subparsers(dest="command", required=True)
    sub.add_parser("mute", help="mute the active TV source(s)")
    sub.add_parser("status", help="show the active TV source(s), read-only")
    volume = sub.add_parser("volume", help="step the active TV source volume")
    volume.add_argument("direction", choices=("up", "down"))
    volume.add_argument("--step-db", type=step_value, default=DEFAULT_STEP_DB)
    return cli


def run(args, client_factory=connect, out=None, err=None):
    out = out or sys.stdout
    err = err or sys.stderr
    try:
        client = client_factory()
        scene, sources = active_sources(client)
        if not sources:
            print("no active TV source on the program scene; nothing changed", file=err)
            return EXIT_NO_SOURCE
        if args.command == "status":
            do_status(client, scene, sources, out)
        elif args.command == "mute":
            do_mute(client, sources, out)
        else:
            do_volume(client, sources, args.direction, args.step_db, out)
    except TvAudioError as exc:
        print(f"obs-tv-audio: {exc}", file=err)
        return EXIT_ERROR
    except Exception as exc:  # connection/auth/protocol failure; never echo secrets
        print(f"obs-tv-audio: OBS request failed ({type(exc).__name__})", file=err)
        return EXIT_ERROR
    return 0


def main(argv=None):
    return run(parser().parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())
