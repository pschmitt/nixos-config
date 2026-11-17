"""Run only on an isolated worker: creates its own private PipeWire session."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

spec = importlib.util.spec_from_file_location(
    "bridge", Path(__file__).with_name("obs-broadcast-audio.py")
)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


def wait_for(callback, message):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        try:
            if callback():
                return
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            pass
        time.sleep(0.1)
    raise AssertionError(message)


def main():
    root = Path(os.environ["TEST_SCRATCH"])
    root.mkdir(mode=0o700)
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    config = root / "config"
    pw_config = config / "pipewire/pipewire.conf.d"
    wp_config = config / "wireplumber/wireplumber.conf.d"
    pw_config.mkdir(parents=True)
    wp_config.mkdir(parents=True)
    (pw_config / "test.conf").write_text(json.dumps({"context.objects": [{
        "factory": "adapter", "args": {
            "factory.name": "support.null-audio-sink",
            "media.class": "Audio/Source/Virtual", "node.name": "meeting_source",
            "audio.position": ["FL", "FR"],
            "adapter.auto-port-config": {"mode": "dsp", "monitor": False, "position": "preserve"},
        },
    }]}))
    script = Path(__file__).with_name("wireplumber") / "meeting-mic.lua"
    (wp_config / "test.conf").write_text(json.dumps({
        "wireplumber.components": [{
            "name": str(script.resolve()), "type": "script/lua", "provides": "custom.meeting-mic",
        }],
        "wireplumber.profiles": {"main": {"custom.meeting-mic": "required"}},
    }))
    os.environ.update(XDG_RUNTIME_DIR=str(runtime), XDG_CONFIG_HOME=str(config))
    processes = []
    with (root / "audio.log").open("w") as log:
        try:
            for command in (["pipewire"], ["pipewire-pulse"], ["wireplumber"]):
                processes.append(subprocess.Popen(command, stdout=log, stderr=log))
            wait_for(lambda: "meeting_source" in bridge.run("pactl", "list", "short", "sources"),
                     "private audio server did not start")
            module = bridge.run(
                "pactl", "load-module", "module-null-sink", "sink_name=obs_broadcast",
                'sink_properties=device.description="OBS Broadcast" device.class=filter node.virtual=true priority.session=0',
                "rate=48000", "channels=2", "channel_map=front-left,front-right",
            )
            process = subprocess.Popen(bridge.bridge_command(), stdout=log, stderr=log)
            processes.append(process)

            def graph_connected():
                graph = json.loads(bridge.run("pw-dump"))
                nodes = {o["id"]: o.get("info", {}).get("props", {}) for o in graph
                         if o["type"] == "PipeWire:Interface:Node"}
                links = [o["info"] for o in graph if o["type"] == "PipeWire:Interface:Link"]
                feed = next((i for i, p in nodes.items() if p.get("node.name") == "obs_broadcast_feed"), None)
                sink = next((i for i, p in nodes.items() if p.get("node.name") == "obs_broadcast"), None)
                mic = next((i for i, p in nodes.items() if p.get("node.name") == "meeting_source"), None)
                capture = next((i for i, p in nodes.items() if p.get("stream.capture.sink") in (True, "true")), None)
                if None in (feed, sink, mic, capture):
                    return False
                outgoing = [link for link in links if link["output-node-id"] == feed]
                incoming = [link for link in links if link["input-node-id"] == capture]
                return (len(outgoing) == 2 and len(incoming) == 2
                        and all(link["input-node-id"] == mic for link in outgoing)
                        and all(link["output-node-id"] == sink for link in incoming))

            wait_for(graph_connected, "bridge did not exclusively link OBS sink to Meeting Microphone")
            bridge.run("pactl", "unload-module", module)
            time.sleep(0.3)
            graph = json.loads(bridge.run("pw-dump"))
            captures = {o["id"] for o in graph if o["type"] == "PipeWire:Interface:Node"
                        and o.get("info", {}).get("props", {}).get("stream.capture.sink") in (True, "true")}
            assert not any(o["type"] == "PipeWire:Interface:Link"
                           and o["info"]["input-node-id"] in captures for o in graph), "capture fell back"
            print("Live isolated PipeWire graph passed: exact sink capture, meeting-only playback, no fallback")
        finally:
            for process in reversed(processes):
                bridge.stop_process(process)


if __name__ == "__main__":
    main()
