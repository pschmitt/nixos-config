"""Discover a local Syncthing instance without invoking external commands."""

from __future__ import annotations

from dataclasses import dataclass
import ipaddress
import os
from pathlib import Path
from typing import Iterable
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET


@dataclass(frozen=True)
class Folder:
    id: str
    path: Path


@dataclass(frozen=True)
class Endpoint:
    url: str
    api_key: str
    certificate: Path | None = None


@dataclass(frozen=True)
class SyncthingConfiguration:
    folders: tuple[Folder, ...]
    endpoint: Endpoint | None


def normalise_local_path(path: str | Path) -> Path:
    """Normalise local paths without resolving symlinks during enumeration."""
    return Path(os.path.normpath(os.path.abspath(os.path.expanduser(str(path)))))


def path_is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def folder_for_path(folders: Iterable[Folder], path: str | Path) -> Folder | None:
    path = normalise_local_path(path)
    candidates = [folder for folder in folders if path_is_within(path, folder.path)]
    return max(candidates, key=lambda folder: len(folder.path.parts), default=None)


def relative_to_folder(path: str | Path, folder: Folder) -> str:
    relative = normalise_local_path(path).relative_to(folder.path)
    return "" if str(relative) == "." else relative.as_posix()


def _config_directories(environ: dict[str, str]) -> list[Path]:
    home = Path.home()
    candidates = [
        environ.get("SYNCTHING_CONFIG_DIR"),
        environ.get("STCONFDIR"),
        environ.get("STHOMEDIR"),
        Path(environ.get("XDG_STATE_HOME", home / ".local/state")) / "syncthing",
        home / ".local/state/syncthing",
        Path(environ.get("XDG_CONFIG_HOME", home / ".config")) / "syncthing",
        home / ".config/syncthing",
    ]
    result: list[Path] = []
    for candidate in candidates:
        if not candidate:
            continue
        path = normalise_local_path(candidate)
        if path not in result:
            result.append(path)
    return result


def _local_url(url: str) -> str | None:
    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError:
        return None
    if parsed.scheme not in {"http", "https"} or parsed.username or parsed.password:
        return None
    if parsed.path not in {"", "/"} or parsed.query or parsed.fragment:
        return None
    host = parsed.hostname
    if not host:
        return None
    if host == "localhost":
        pass
    else:
        try:
            if not ipaddress.ip_address(host).is_loopback:
                return None
        except ValueError:
            return None
    display_host = f"[{host}]" if ":" in host else host
    return f"{parsed.scheme}://{display_host}{f':{port}' if port else ''}"


def _url_from_gui(address: str, tls: bool) -> str | None:
    address = address.strip()
    if address.startswith("/"):
        return None  # UNIX sockets need a non-stdlib HTTP transport.
    if address.startswith("[::]"):
        address = address.replace("[::]", "[::1]", 1)
    elif address.startswith("0.0.0.0") or address.startswith(":"):
        address = f"127.0.0.1{address[address.rfind(':') :]}"
    return _local_url(f"{'https' if tls else 'http'}://{address}")


def discover(environ: dict[str, str] | None = None) -> SyncthingConfiguration:
    """Read the first usable local ``config.xml`` and apply safe env overrides."""
    environ = dict(os.environ if environ is None else environ)
    for config_dir in _config_directories(environ):
        config_path = config_dir / "config.xml"
        try:
            root = ET.parse(config_path).getroot()
        except (ET.ParseError, OSError):
            continue

        folders = tuple(
            Folder(id=element.attrib["id"], path=normalise_local_path(element.attrib["path"]))
            for element in root.findall("folder")
            if element.attrib.get("id") and element.attrib.get("path")
        )
        gui = root.find("gui")
        if gui is None or gui.attrib.get("enabled", "true").lower() != "true":
            return SyncthingConfiguration(folders=folders, endpoint=None)

        api_key = environ.get("SYNCTHING_API_KEY") or (gui.findtext("apikey") or "").strip()
        configured_url = _url_from_gui(
            gui.findtext("address") or "127.0.0.1:8384",
            gui.attrib.get("tls", "false").lower() == "true",
        )
        url = _local_url(environ.get("SYNCTHING_URL", "")) if environ.get("SYNCTHING_URL") else configured_url
        certificate = config_dir / "https-cert.pem" if url and url.startswith("https://") else None
        endpoint = Endpoint(url, api_key, certificate if certificate and certificate.is_file() else None) if url and api_key else None
        return SyncthingConfiguration(folders=folders, endpoint=endpoint)
    return SyncthingConfiguration(folders=(), endpoint=None)
