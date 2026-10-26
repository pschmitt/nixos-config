"""Thread-safe cache with no Nautilus or GObject dependency."""

from __future__ import annotations

from dataclasses import dataclass
import threading
import time

from .discovery import Folder, SyncthingConfiguration, folder_for_path, relative_to_folder
from .model import FolderSnapshot, Status


@dataclass(frozen=True)
class CachedSnapshot:
    snapshot: FolderSnapshot
    created_at: float


class StatusCache:
    """Cache folder snapshots, short failures, and safe path resolution."""

    def __init__(self, *, ttl: float = 30.0, retry_delay: float = 5.0) -> None:
        self.ttl = ttl
        self.retry_delay = retry_delay
        self._configuration = SyncthingConfiguration(folders=(), endpoint=None)
        self._snapshots: dict[str, CachedSnapshot] = {}
        self._last_attempt: dict[str, float] = {}
        self._lock = threading.RLock()

    @property
    def configuration(self) -> SyncthingConfiguration:
        with self._lock:
            return self._configuration

    def set_configuration(self, configuration: SyncthingConfiguration) -> None:
        with self._lock:
            self._configuration = configuration
            valid_ids = {folder.id for folder in configuration.folders}
            self._snapshots = {key: value for key, value in self._snapshots.items() if key in valid_ids}
            self._last_attempt = {key: value for key, value in self._last_attempt.items() if key in valid_ids}

    def folder_for_path(self, path: str) -> Folder | None:
        with self._lock:
            return folder_for_path(self._configuration.folders, path)

    def status_for(self, path: str, *, is_directory: bool) -> tuple[Folder | None, Status | None]:
        folder = self.folder_for_path(path)
        if folder is None:
            return None, None
        with self._lock:
            cached = self._snapshots.get(folder.id)
        if cached is None:
            return folder, Status.UNKNOWN
        return folder, cached.snapshot.status_for(relative_to_folder(path, folder), is_directory=is_directory)

    def refresh_due(self, folder: Folder, *, now: float | None = None) -> bool:
        now = time.monotonic() if now is None else now
        with self._lock:
            cached = self._snapshots.get(folder.id)
            last_attempt = self._last_attempt.get(folder.id, 0.0)
            if now - last_attempt < self.retry_delay:
                return False
            return cached is None or now - cached.created_at >= self.ttl

    def mark_refresh_attempt(self, folder: Folder, *, now: float | None = None) -> None:
        with self._lock:
            self._last_attempt[folder.id] = time.monotonic() if now is None else now

    def store(self, folder: Folder, snapshot: FolderSnapshot, *, now: float | None = None) -> None:
        with self._lock:
            self._snapshots[folder.id] = CachedSnapshot(snapshot, time.monotonic() if now is None else now)

    def invalidate(self, folder_id: str | None = None) -> None:
        with self._lock:
            if folder_id is None:
                self._snapshots.clear()
            else:
                self._snapshots.pop(folder_id, None)
