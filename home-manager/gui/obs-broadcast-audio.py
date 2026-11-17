#!/usr/bin/env python3
"""Opt-in, watchdog-protected OBS broadcast bridge: Meeting Microphone plus local output."""

import argparse
import contextlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

UNIT = "obs-broadcast-audio.service"
GUARD_INTERVAL = 0.5
POLL_INTERVAL = 0.02


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def read_status(directory, now=None):
    try:
        timestamp, enabled, routing, error = (directory / "status").read_text().splitlines()[:4]
        age = (time.time() if now is None else now) - int(timestamp)
        return {
            "fresh": 0 <= age < 2,
            "enabled": enabled == "enabled",
            "routing": routing == "routing",
            "error": error,
        }
    except (OSError, ValueError):
        return {"fresh": False, "enabled": False, "routing": False, "error": ""}


def stop_processes(processes):
    """Stop all branches at once, the local monitor first.

    Only the local branch can be heard on the user's own output, so it is
    signalled first and nothing waits for the meeting branch before it is gone.
    """
    for process in reversed(processes):
        process.terminate()
    for process in reversed(processes):
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def bridge_command():
    return [
        "pw-loopback", "--name", "obs-broadcast-audio", "--channels", "2",
        "--capture", "obs_broadcast",
        "--capture-props", json.dumps({
            "stream.capture.sink": True,
            "node.dont-fallback": True,
            "node.dont-reconnect": True,
        }),
        "--playback-props", json.dumps({
            "node.name": "obs_broadcast_feed",
            "node.autoconnect": False,
            "meeting-mic.feed": True,
        }),
    ]


def local_command():
    """Monitor-only branch: the OBS sink to whatever the desktop's output is.

    No target is set, so the session manager keeps the stream on the current
    default output (speakers, headphones, Bluetooth) and moves it when that
    changes. Never tagged for Meeting Microphone.
    """
    return [
        "pw-loopback", "--name", "obs-broadcast-local", "--channels", "2",
        "--capture", "obs_broadcast",
        "--capture-props", json.dumps({
            "stream.capture.sink": True,
            "node.dont-fallback": True,
            "node.dont-reconnect": True,
        }),
        "--playback-props", json.dumps({"node.name": "obs_broadcast_local"}),
    ]


def local_output_loops():
    """True if the local branch would play back into the OBS sink it captures."""
    if run("pactl", "get-default-sink") == "obs_broadcast":
        return True
    sinks = {
        str(sink["index"]): sink["name"]
        for sink in json.loads(run("pactl", "-f", "json", "list", "sinks"))
    }
    return any(
        stream.get("properties", {}).get("node.name") == "obs_broadcast_local"
        and sinks.get(str(stream.get("sink"))) == "obs_broadcast"
        for stream in json.loads(run("pactl", "-f", "json", "list", "sink-inputs"))
    )


def start_bridges():
    """Start the meeting and the local branch together, or neither."""
    if local_output_loops():
        raise RuntimeError("The default audio output is the OBS Broadcast sink; audio route closed.")
    started = []
    try:
        for command in (bridge_command(), local_command()):
            started.append(subprocess.Popen(command, stdout=subprocess.DEVNULL))
    except BaseException:
        stop_processes(started)
        raise
    return started


def cleanup(directory):
    try:
        module = (directory / "module").read_text().strip()
    except FileNotFoundError:
        return
    sinks = json.loads(run("pactl", "-f", "json", "list", "sinks"))
    if any(sink["name"] == "obs_broadcast" and str(sink.get("owner_module")) == module
           for sink in sinks):
        run("pactl", "unload-module", module)
    (directory / "module").unlink(missing_ok=True)


def serve(directory):
    directory.mkdir(mode=0o700, exist_ok=True)
    request = directory / "requested"
    request.unlink(missing_ok=True)
    module = None
    processes = []
    stopping = False

    def stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        sources = json.loads(run("pactl", "-f", "json", "list", "sources"))
        if not any(source["name"] == "meeting_source" for source in sources):
            raise RuntimeError("Meeting Microphone is unavailable.")
        sinks = json.loads(run("pactl", "-f", "json", "list", "sinks"))
        if any(sink["name"] == "obs_broadcast" for sink in sinks):
            raise RuntimeError("OBS Broadcast sink already exists; refusing to take ownership.")
        module = run(
            "pactl", "load-module", "module-null-sink", "sink_name=obs_broadcast",
            'sink_properties=device.description="OBS Broadcast" device.class=filter node.virtual=true priority.session=0',
            "rate=48000", "channels=2", "channel_map=front-left,front-right",
        )
        (directory / "module").write_text(module)
        request.touch(mode=0o600)
        deadline = time.monotonic() + 3
        guarded = 0.0
        acknowledged = False
        while not stopping:
            status = read_status(directory)
            if status["fresh"] and status["error"]:
                raise RuntimeError(status["error"])
            ready = status["fresh"] and status["enabled"]
            acknowledged = acknowledged or ready
            if not request.exists():
                raise RuntimeError("OBS script disarmed the audio route.")
            if not ready and (acknowledged or time.monotonic() >= deadline):
                raise RuntimeError("OBS script is unavailable; audio route closed.")
            routing = ready and status["routing"]
            if any(process.poll() is not None for process in processes):
                raise RuntimeError("PipeWire bridge exited; audio route closed.")
            if routing and not processes:
                processes = start_bridges()
                guarded = time.monotonic()
            elif not routing and processes:
                stop_processes(processes)
                processes = []
            elif processes and time.monotonic() - guarded >= GUARD_INTERVAL:
                guarded = time.monotonic()
                if local_output_loops():
                    raise RuntimeError(
                        "The default audio output became the OBS Broadcast sink; audio route closed."
                    )
            time.sleep(POLL_INTERVAL)
    finally:
        request.unlink(missing_ok=True)
        stop_processes(processes)
        if module:
            deadline = time.monotonic() + 0.5
            while time.monotonic() < deadline:
                status = read_status(directory)
                if status["fresh"] and not status["enabled"]:
                    break
                time.sleep(0.05)
            with contextlib.suppress(subprocess.CalledProcessError):
                run("pactl", "unload-module", module)
                (directory / "module").unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("on", "off", "toggle", "status", "run", "cleanup"))
    args = parser.parse_args()
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        parser.error("XDG_RUNTIME_DIR is required")
    directory = Path(runtime) / "obs-broadcast-audio"
    if args.action == "run":
        serve(directory)
        return
    if args.action == "cleanup":
        cleanup(directory)
        return
    active = subprocess.run(
        ["systemctl", "--user", "is-active", "--quiet", UNIT], check=False
    ).returncode == 0
    action = args.action
    if action == "toggle":
        action = "off" if active else "on"
    if action == "off":
        (directory / "requested").unlink(missing_ok=True)
        run("systemctl", "--user", "stop", UNIT)
        print("OBS broadcast audio: off")
    elif action == "on":
        if not active:
            (directory / "status").unlink(missing_ok=True)
            # Best effort: systemd reports "Unit not loaded" (exit 1) for a service
            # that never ran, which is not a reason to abort the start.
            subprocess.run(
                ["systemctl", "--user", "reset-failed", UNIT], check=False, capture_output=True
            )
            run("systemctl", "--user", "start", UNIT)
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            status = read_status(directory)
            if status["fresh"] and status["error"]:
                raise RuntimeError(status["error"])
            if status["fresh"] and status["enabled"] and (directory / "requested").exists():
                print("OBS broadcast audio: on (only ARD / ZDF / Tagesschau program scenes)")
                return
            if subprocess.run(
                ["systemctl", "--user", "is-active", "--quiet", UNIT], check=False
            ).returncode != 0:
                raise RuntimeError(
                    "Audio routing service failed. Check: journalctl --user -u " + UNIT
                )
            time.sleep(0.1)
        run("systemctl", "--user", "stop", UNIT)
        raise RuntimeError("Load obs-broadcast-audio.lua in OBS Tools → Scripts first.")
    else:
        status = read_status(directory)
        enabled = active and status["fresh"] and status["enabled"]
        print("OBS broadcast audio: " + (
            "on, routing stream audio to the meeting and the default output" if enabled and status["routing"] else
            "on, waiting for an eligible program scene" if enabled else "off"
        ))
        if active and not status["fresh"]:
            print("OBS script heartbeat unavailable; route is closing.")
        if status["fresh"] and status["error"]:
            print(status["error"])


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error) if isinstance(error, RuntimeError) else
              "Audio routing command failed; inspect the user service journal.", file=sys.stderr)
        sys.exit(1)
