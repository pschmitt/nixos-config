"""Nautilus entry point. This file is installed in nautilus-python/extensions."""

from __future__ import annotations

from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

import gi

gi.require_version("Nautilus", "4.1")
from gi.repository import GLib, GObject, Nautilus


PACKAGE_ROOT = Path(__file__).resolve().parents[2] / "syncthing-nautilus"
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from syncthing_nautilus.extension import ExtensionCore


class SyncthingStatusExtension(GObject.GObject, Nautilus.InfoProvider):
    """Add cached Syncthing status emblems for local Nautilus files."""

    def __init__(self) -> None:
        super().__init__()
        self._core = ExtensionCore(GLib.idle_add)

    def update_file_info(self, file_info: Nautilus.FileInfo) -> None:
        try:
            if file_info.get_uri_scheme() != "file":
                return
            path = unquote(urlsplit(file_info.get_uri()).path)
            if not path:
                return
            self._core.update_file_info(file_info, path, is_directory=file_info.is_directory())
        except Exception:
            # Extension boundaries must be fail-closed: Nautilus remains usable.
            return
