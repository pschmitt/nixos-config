"""Shared ADB device alias resolution for the TermuxPP host helpers.

Aliases live in a runtime JSON file (never in the repository), by default
``$XDG_CONFIG_HOME/termuxpp/adb-devices.json``::

    {
      "version": 1,
      "devices": {
        "phone": {
          "serials": ["USB_SERIAL", "192.0.2.10:5555"],
          "serial_prefixes": ["adb-USB_SERIAL-"],
          "metadata": {"model": ["MODEL"]},
          "credential_dir": "~/optional/explicit/credential/dir",
          "ssh": {"port": 2222, "start_argv": ["sh", "-c", "..."]}
        }
      }
    }

An alias names candidate ADB serials (exact or prefix) and/or exact ``adb devices -l``
metadata values (``model``, ``device``, ``product``). The candidates are matched
against ``adb devices -l`` at resolution time; exactly one must be in the ``device``
state, otherwise resolution fails instead of guessing. A name that is not a
configured alias is used verbatim as a raw ADB serial.
"""

import hashlib
import json
import os
import re
import stat
import subprocess
from dataclasses import dataclass, field
from pathlib import Path


CONFIG_ENV = "TERMUXPP_ADB_DEVICES"
_CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "termuxpp"
DEFAULT_CONFIG = _CONFIG_HOME / "adb-devices.json"
DEFAULT_CREDENTIAL_DIR = _CONFIG_HOME / "adb-shell"
DEFAULT_SSH_PORT = 2222
MAX_CONFIG_BYTES = 64 * 1024
METADATA_KEYS = ("model", "device", "product")
ALIAS_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z")


@dataclass(frozen=True)
class Alias:
    name: str
    serials: tuple = ()
    serial_prefixes: tuple = ()
    metadata: tuple = ()
    credential_dir: Path = None
    ssh_port: int = DEFAULT_SSH_PORT
    ssh_start_argv: tuple = ()

    def matches(self, serial, metadata=None):
        metadata = metadata or {}
        return (serial in self.serials or any(serial.startswith(prefix) for prefix in self.serial_prefixes)
                or any(metadata.get(key) in values for key, values in self.metadata))


@dataclass(frozen=True)
class Device:
    serial: str
    credential_dir: Path
    alias: Alias = field(default=None)
    credential_error: str = None  # set when the credential directory is ambiguous; fatal only when credentials are used


def _text(value, what, limit=128):
    if (not isinstance(value, str) or not value or len(value) > limit or not value.isascii()
            or any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in value)):
        raise RuntimeError(f"Invalid {what} in the device configuration.")
    return value


def _strings(value, what):
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise RuntimeError(f"{what} must be a list of strings in the device configuration.")
    return [_text(item, what) for item in value]


def _only(mapping, allowed, what):
    if not isinstance(mapping, dict) or set(mapping) - set(allowed):
        raise RuntimeError(f"Unsupported or malformed {what} in the device configuration.")


def _parse_alias(name, entry):
    if not ALIAS_RE.match(name):
        raise RuntimeError("Invalid alias name in the device configuration.")
    _only(entry, ("serials", "serial_prefixes", "metadata", "credential_dir", "ssh"), f"alias {name!r}")
    serials = _strings(entry.get("serials", []), "serials")
    prefixes = _strings(entry.get("serial_prefixes", []), "serial_prefixes")
    metadata = entry.get("metadata", {})
    _only(metadata, METADATA_KEYS, "metadata section")
    metadata = tuple((key, tuple(_strings(values, f"metadata.{key}"))) for key, values in metadata.items())
    if not serials and not prefixes and not metadata:
        raise RuntimeError(f"Alias {name!r} needs serials, serial_prefixes or metadata.")
    credential_dir = entry.get("credential_dir")
    if credential_dir is not None:
        if not isinstance(credential_dir, str) or not credential_dir or "\0" in credential_dir:
            raise RuntimeError("Invalid credential_dir in the device configuration.")
        credential_dir = Path(credential_dir).expanduser()
        if not credential_dir.is_absolute():
            raise RuntimeError("credential_dir must be an absolute path.")
    ssh = entry.get("ssh", {})
    _only(ssh, ("port", "start_argv"), "ssh section")
    port = ssh.get("port", DEFAULT_SSH_PORT)
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise RuntimeError("ssh.port must be a TCP port number.")
    argv = ssh.get("start_argv", [])
    if (not isinstance(argv, list) or len(argv) > 64
            or not all(isinstance(a, str) and len(a) <= 4096 and "\0" not in a for a in argv)
            or (argv and (not argv[0] or argv[0].startswith("-")))):
        raise RuntimeError("ssh.start_argv must be a list of up to 64 strings starting with an executable.")
    return Alias(name, tuple(serials), tuple(prefixes), metadata, credential_dir, port, tuple(argv))


def load_aliases(path=None):
    """Return {name: Alias}. A missing default config means no aliases; an explicit one must exist."""
    explicit = path is not None or bool(os.environ.get(CONFIG_ENV))
    path = Path(path or os.environ.get(CONFIG_ENV) or DEFAULT_CONFIG)
    try:
        descriptor = os.open(path, os.O_RDONLY)
    except FileNotFoundError:
        if explicit:
            raise RuntimeError(f"Device configuration {path} does not exist.") from None
        return {}
    with os.fdopen(descriptor, "rb") as handle:
        status = os.fstat(handle.fileno())
        if not stat.S_ISREG(status.st_mode) or status.st_uid not in (os.getuid(), 0) or status.st_mode & 0o022:
            raise RuntimeError("Device configuration must be a regular file owned by you and not writable by others.")
        data = handle.read(MAX_CONFIG_BYTES + 1)
    if len(data) > MAX_CONFIG_BYTES:
        raise RuntimeError("Device configuration is too large.")
    try:
        document = json.loads(data)
    except (UnicodeDecodeError, ValueError):
        raise RuntimeError("Device configuration is not valid JSON.") from None
    _only(document, ("version", "devices"), "top level")
    if document.get("version") != 1 or not isinstance(document.get("devices"), dict):
        raise RuntimeError("Device configuration needs version 1 and a devices object.")
    return {name: _parse_alias(name, entry) for name, entry in document["devices"].items()}


def list_adb_devices(timeout=15):
    """Return [(serial, state, metadata)] from ``adb devices -l``."""
    try:
        result = subprocess.run(["adb", "devices", "-l"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, timeout=timeout)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        raise RuntimeError("Could not list ADB devices; is adb installed and its server responsive?") from None
    if result.returncode != 0:
        raise RuntimeError("Could not list ADB devices; is adb installed and its server responsive?")
    devices = []
    for line in result.stdout.splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 2 and not line.startswith("*"):
            metadata = dict(field.split(":", 1) for field in fields[2:] if ":" in field)
            devices.append((fields[0], fields[1], metadata))
    return devices


def credential_dir_for(serial, alias=None, root=None):
    """Stable credential directory; existing credentials are reused and never copied or replaced.

    Order for an alias: explicit ``credential_dir``; its stable ``aliases/NAME`` directory when it
    already holds credentials; the legacy per-serial directory (of the resolved serial or of any exact
    serial the alias lists) when exactly one holds credentials; else ``aliases/NAME`` (the target of an
    explicit ``--provision``). Several legacy directories are an error: identities are never merged.
    Raw serials keep the legacy layout.
    """
    root = Path(root or DEFAULT_CREDENTIAL_DIR)

    def legacy_for(name):
        return root / hashlib.sha256(name.encode("utf-8")).hexdigest()

    if alias is None:
        return legacy_for(serial)
    if alias.credential_dir is not None:
        return alias.credential_dir
    stable = root / "aliases" / alias.name
    if (stable / "client.key").exists():
        return stable
    existing = [legacy_for(name) for name in dict.fromkeys((serial, *alias.serials))
                if (legacy_for(name) / "client.key").exists()]
    if len(existing) > 1:
        raise RuntimeError(f"Alias {alias.name!r} has credentials for several of its serials; "
                           "set credential_dir for it to choose one.")
    return existing[0] if existing else stable


def resolve_device(name, config_path=None, adb_devices=None, credential_root=None):
    """Resolve an alias or raw serial once; callers must use the returned serial throughout."""
    alias = load_aliases(config_path).get(name)
    if alias is None:
        return Device(name, credential_dir_for(name, None, credential_root))
    listing = [(entry + ({},))[:3] for entry in (adb_devices or list_adb_devices)()]
    candidates = {serial: state for serial, state, metadata in listing if alias.matches(serial, metadata)}
    ready = sorted(serial for serial, state in candidates.items() if state == "device")
    if len(ready) == 1:
        try:
            return Device(ready[0], credential_dir_for(ready[0], alias, credential_root), alias)
        except RuntimeError as error:
            stable = Path(credential_root or DEFAULT_CREDENTIAL_DIR) / "aliases" / alias.name
            return Device(ready[0], stable, alias, str(error))
    if ready:
        raise RuntimeError(f"Alias {name!r} is ambiguous: ready candidates {', '.join(ready)}; "
                           "disconnect all but one transport.")
    if candidates:
        states = ", ".join(f"{serial} ({state})" for serial, state in sorted(candidates.items()))
        raise RuntimeError(f"Alias {name!r} has no ready device: {states}.")
    raise RuntimeError(f"Alias {name!r} matches no connected ADB device.")
