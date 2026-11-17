#!/usr/bin/env python3
"""Register a Lua script in the active OBS scene collection.

OBS keeps its scripts in the scene collection JSON, under
modules["scripts-tool"] as a list of {"path": ..., "settings": {...}}.
This helper appends one entry for the script and leaves everything else
alone. It only touches the file while OBS is not running, because OBS
rewrites the whole collection from memory when it exits and would silently
drop the change.

Exit codes: 0 ok (registered, already registered or nothing to do),
75 deferred because OBS is running, 3 not registered (--check only),
1 error. Output never contains scene or script settings data.
"""

import argparse
import json
import os
import stat
import sys
import tempfile
from pathlib import Path

PREFIX = "obs-register-script:"
EX_TEMPFAIL = 75
OBS_COMM = {"obs", ".obs-wrapped", "obs-wrapped"}
SCRIPT_NAME = "obs-broadcast-audio.lua"


class RegistrationError(Exception):
    pass


def say(message, quiet=False, error=False):
    if quiet and not error:
        return
    print(f"{PREFIX} {message}", file=sys.stderr if error else sys.stdout)


def obs_running(proc=Path("/proc")):
    """True when a process of the current user runs OBS."""
    uid = os.getuid()
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != uid:
                continue
            if (entry / "comm").read_text().strip() in OBS_COMM:
                return True
        except OSError:
            continue
    return False


def read_basic_value(ini, keys):
    """Return the first of keys found in the [Basic] section of an OBS ini."""
    try:
        text = ini.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    section = None
    found = {}
    for raw in text.splitlines():
        line = raw.strip().lstrip("﻿")
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
        elif section == "Basic" and "=" in line:
            key, _, value = line.partition("=")
            found.setdefault(key.strip(), value.strip())
    for key in keys:
        if found.get(key):
            return found[key]
    return None


def active_collection(config_dir):
    for name in ("user.ini", "global.ini"):
        ini = config_dir / name
        value = read_basic_value(ini, ("SceneCollectionFile",))
        if value is None:
            value = read_basic_value(ini, ("SceneCollection",))
        if value:
            if "/" in value or value in (".", "..") or "\0" in value:
                raise RegistrationError("unsafe scene collection name")
            if not value.endswith(".json"):
                value += ".json"
            return config_dir / "basic" / "scenes" / value
    return None


def same_file(a, b):
    try:
        return os.path.realpath(a) == os.path.realpath(b)
    except OSError:
        return False


def find_entry(scripts, script):
    """Return (index, state) of the entry for script.

    state is "match" for the very same file, "stale" for an entry of the same
    name whose file no longer exists (eg. an old store path) and "other" for an
    entry of the same name that points to a different, existing file.
    """
    for index, entry in enumerate(scripts):
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            continue
        path = entry["path"]
        if path == str(script) or same_file(path, script):
            return index, "match"
    for index, entry in enumerate(scripts):
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            continue
        if os.path.basename(entry["path"]) == script.name:
            return index, "other" if os.path.exists(entry["path"]) else "stale"
    return None, None


def scripts_list(collection, create):
    modules = collection.get("modules")
    if modules is None and create:
        modules = collection["modules"] = {}
    if not isinstance(modules, dict):
        if create:
            raise RegistrationError("unexpected modules layout")
        return None
    scripts = modules.get("scripts-tool")
    if scripts is None and create:
        scripts = modules["scripts-tool"] = []
    if scripts is not None and not isinstance(scripts, list):
        raise RegistrationError("unexpected scripts-tool layout")
    return scripts


def write_atomic(path, data, mode, backup):
    """Replace path with data (bytes); keep a private backup of the old file."""
    directory = path.parent
    if backup:
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=f".{path.name}.bak-")
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(path.read_bytes())
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(tmp, 0o600)
            os.replace(tmp, f"{path}.obs-register.bak")
        except BaseException:
            Path(tmp).unlink(missing_ok=True)
            raise
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=f".{path.name}.new-")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise
    dir_fd = os.open(directory, os.O_RDONLY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)


def register(config_dir, script, check=False, quiet=False, proc=Path("/proc")):
    if not script.exists():
        say("script is not installed, nothing to register", quiet)
        return 0
    collection_file = active_collection(config_dir)
    if collection_file is None or not collection_file.is_file():
        say("no active scene collection file found, nothing to do", quiet)
        return 0

    before = collection_file.stat()
    raw = collection_file.read_bytes()
    try:
        collection = json.loads(raw)
    except ValueError as exc:
        raise RegistrationError(f"scene collection is not valid JSON: {exc.__class__.__name__}")
    if not isinstance(collection, dict):
        raise RegistrationError("scene collection is not a JSON object")

    scripts = scripts_list(collection, create=False)
    index, state = find_entry(scripts or [], script)
    if state == "match":
        say("script already registered", quiet)
        return 0
    if check:
        say("script not registered")
        return 3
    if state == "other":
        say("a script of that name is registered from another path, leaving it", quiet)
        return 0

    if obs_running(proc):
        say("OBS is running, deferred until it is closed")
        return EX_TEMPFAIL

    scripts = scripts_list(collection, create=True)
    if state == "stale":
        scripts[index]["path"] = str(script)
        action = "repointed stale registration"
    else:
        scripts.append({"path": str(script), "settings": {}})
        action = "registered script"

    # OBS writes 4-space indented JSON without a trailing newline; keep the
    # file's own convention so the diff is just the new entry.
    newline = "\n" if raw.endswith(b"\n") else ""
    data = (json.dumps(collection, indent=4, ensure_ascii=False) + newline).encode()
    json.loads(data)

    # OBS may have been started or the file rewritten since we read it.
    after = collection_file.stat()
    if (after.st_mtime_ns, after.st_size, after.st_ino) != (
        before.st_mtime_ns,
        before.st_size,
        before.st_ino,
    ) or obs_running(proc):
        say("scene collection changed meanwhile, deferred")
        return EX_TEMPFAIL

    write_atomic(collection_file, data, stat.S_IMODE(before.st_mode), backup=True)
    say(f"{action} in the active scene collection", quiet)
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--config-dir", type=Path)
    parser.add_argument("--script", type=Path)
    parser.add_argument("--check", action="store_true", help="only report, never write")
    parser.add_argument("--quiet", action="store_true", help="only print errors and deferrals")
    args = parser.parse_args(argv)

    config_dir = args.config_dir or (
        Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "obs-studio"
    )
    script = args.script or config_dir / "scripts" / SCRIPT_NAME
    try:
        return register(config_dir, script, check=args.check, quiet=args.quiet)
    except (RegistrationError, OSError) as exc:
        say(f"failed: {exc.__class__.__name__}: {exc}", error=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
