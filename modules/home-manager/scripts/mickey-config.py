"""Apply declared settings while retaining Mickey's writable pairing config."""

import os
import pathlib
import sys
import tempfile
from collections.abc import Mapping

import tomlkit


def merge_settings(current, desired):
    for key, value in desired.items():
        if isinstance(value, Mapping) and isinstance(current.get(key), Mapping):
            merge_settings(current[key], value)
        else:
            current[key] = value


def apply_settings(path, desired):
    original = path.read_text() if path.exists() else ""
    current = tomlkit.parse(original)
    peers = desired.pop("peer", [])
    merge_settings(current, desired)

    if peers:
        if "peer" not in current:
            current["peer"] = tomlkit.aot()
        for declared in peers:
            matches = [peer for peer in current["peer"] if peer.get("name") == declared["name"]]
            if len(matches) > 1:
                raise ValueError(f"Multiple Mickey peers are named {declared['name']!r}")
            if matches:
                merge_settings(matches[0], declared)
            else:
                current["peer"].append(declared)

    updated = tomlkit.dumps(current)
    if updated == original:
        return

    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        temporary = pathlib.Path(stream.name)
        try:
            stream.write(updated)
            stream.close()
            if (path.read_text() if path.exists() else "") != original:
                raise RuntimeError("Mickey's settings changed while applying managed options")
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    config, managed = map(pathlib.Path, sys.argv[1:])
    apply_settings(config.resolve(), tomlkit.parse(managed.read_text()))
