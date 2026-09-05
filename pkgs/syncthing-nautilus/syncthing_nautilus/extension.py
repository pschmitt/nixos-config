"""Non-blocking Nautilus adapter logic; GI is injected by the loader module."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import logging
import os
import threading
import time
from typing import Any, Callable

from .cache import StatusCache
from .discovery import SyncthingConfiguration, discover
from .model import Status
from .syncthing import SyncthingClient, SyncthingUnavailable


EMBLEMS = {
    # Names chosen from Adwaita's actual icon set: Adwaita ships no
    # "emblem-synchronized"/"sync-*" icons, so those names silently drew
    # nothing regardless of everything else working.
    Status.SYNCED: "object-select-symbolic",
    Status.SYNCING: "content-loading-symbolic",
    Status.ERROR: "dialog-error-symbolic",
    Status.CONFLICT: "emblem-important-symbolic",
}


def _logger() -> logging.Logger:
    logger = logging.getLogger("syncthing-nautilus")
    if os.environ.get("SYNCTHING_NAUTILUS_DEBUG") == "1":
        logger.setLevel(logging.DEBUG)
        if not logger.handlers:
            handler = logging.StreamHandler()
            handler.setFormatter(logging.Formatter("%(name)s: %(message)s"))
            logger.addHandler(handler)
    return logger


class ExtensionCore:
    """Coordinates background API work while all FileInfo access stays on the UI thread."""

    def __init__(self, schedule_main: Callable[..., Any]) -> None:
        self._schedule_main = schedule_main
        self._cache = StatusCache()
        self._executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="syncthing-nautilus")
        self._lock = threading.Lock()
        self._refreshing: set[str] = set()
        # Keep a small, short-lived set of FileInfo instances so a background
        # refresh can ask Nautilus to rerun this provider for visible items.
        self._visible_files: list[tuple[float, Any]] = []
        self._log = _logger()
        # This only reads one small local XML file. It must happen before
        # Nautilus asks about the first directory, otherwise that first view
        # has no matching FileInfo instances to invalidate after discovery.
        self._install_configuration(discover())

    def update_file_info(self, file_info: Any, path: str, *, is_directory: bool) -> None:
        folder, status = self._cache.status_for(path, is_directory=is_directory)
        if folder is None:
            return
        self._visible_files.append((time.monotonic(), file_info))
        emblem = EMBLEMS.get(status)
        if emblem:
            try:
                file_info.add_emblem(emblem)
            except Exception:  # A disappearing item must never affect Nautilus.
                return
        if self._cache.refresh_due(folder):
            self._start_refresh(folder)

    def _install_configuration(self, configuration: SyncthingConfiguration) -> bool:
        self._cache.set_configuration(configuration)
        if configuration.endpoint:
            self._executor.submit(self._event_loop, SyncthingClient(configuration.endpoint))
        self._invalidate_visible()
        return False

    def _start_refresh(self, folder: Any) -> None:
        with self._lock:
            if folder.id in self._refreshing:
                return
            self._refreshing.add(folder.id)
        self._cache.mark_refresh_attempt(folder)
        self._executor.submit(self._refresh_worker, folder)

    def _refresh_worker(self, folder: Any) -> None:
        try:
            endpoint = self._cache.configuration.endpoint
            if endpoint is None:
                return
            self._cache.store(folder, SyncthingClient(endpoint).folder_snapshot(folder))
        except SyncthingUnavailable as error:
            self._log.debug("local API unavailable: %s", error)
        except Exception:
            self._log.debug("unexpected background refresh failure", exc_info=True)
        finally:
            self._schedule_main(self._refresh_finished, folder.id)

    def _refresh_finished(self, folder_id: str) -> bool:
        with self._lock:
            self._refreshing.discard(folder_id)
        self._invalidate_visible()
        return False

    def _event_loop(self, client: SyncthingClient) -> None:
        since = 0
        while True:
            try:
                events = client.events(since)
                for event in events:
                    event_id = event.get("id")
                    if isinstance(event_id, int):
                        since = max(since, event_id)
                if events:
                    self._schedule_main(self._events_received)
            except SyncthingUnavailable as error:
                self._log.debug("event stream unavailable: %s", error)
                time.sleep(5)
            except Exception:
                self._log.debug("unexpected event stream failure", exc_info=True)
                time.sleep(5)

    def _events_received(self) -> bool:
        self._cache.invalidate()
        self._invalidate_visible()
        return False

    def _invalidate_visible(self) -> None:
        # Snapshot first: invalidate_extension_info() can call back into
        # update_file_info() synchronously, which appends to
        # self._visible_files. Iterating the live list would pick up those
        # new entries mid-loop and never terminate for a non-empty directory.
        snapshot = list(self._visible_files)
        retained: list[tuple[float, Any]] = []
        oldest_allowed = time.monotonic() - 120
        for seen_at, file_info in snapshot:
            if seen_at < oldest_allowed:
                continue
            retained.append((seen_at, file_info))
            try:
                file_info.invalidate_extension_info()
            except Exception:
                pass
        self._visible_files = retained[-4096:]
